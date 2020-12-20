// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./StakingRewards.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/IERC721Metadata.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/IERC721Enumerable.sol";
//import "./Circle.sol";

contract CirclePool is StakingPool {
    bytes32 internal constant _stakingThreshold_        = 'stakingThreshold';
    bytes32 internal constant _refererWeight_           = 'refererWeight';
    
    ICircle internal _circle;
    uint256 internal _totalSupplyRefer;
    uint256 internal _totalSupplyCircle;
    mapping(address => uint256) internal _balancesRefer;
    mapping(uint256 => uint256) internal _balancesCircle;
    
    function __CirclePool_init(
        address _governor, 
        address _rewardsDistribution,
        address _rewardsToken,
        address _stakingToken,
        address _ecoAddr,
        address circle_
    ) public virtual initializer {
        super.initialize(_governor, _rewardsDistribution, _rewardsToken, _stakingToken, _ecoAddr);
        __CirclePool_init_unchained(circle_);
    }
    
    function __CirclePool_init_unchained(address circle_) public governance {
        _circle = ICircle(circle_);
        config[_stakingThreshold_]      = 100 ether;
        _setConfig(_refererWeight_, 1, 0.25 ether);
        _setConfig(_refererWeight_, 2, 0.10 ether);
    }

    function totalSupplyRefer() virtual public view returns (uint) {
        return _totalSupplyRefer;
    }
    function totalSupplyCircle() virtual public view returns (uint) {
        return _totalSupplyCircle;
    }
    function totalSupplySum() virtual public view returns (uint) {
        return totalSupply().add(totalSupplyRefer()).add(totalSupplyCircle());
    }

    function balanceReferOf(address acct) virtual public view returns (uint) {
        return _balancesRefer[acct];
    }
    function balanceCircleOf(address acct) virtual public view returns (uint) {
        if(_balances[acct] == 0 || lptNetValue(_balances[acct]) < config[_stakingThreshold_])
            return 0;
        else if(_circle.balanceOf(acct) > 0)
            return _balancesCircle[_circle.tokenOfOwnerByIndex(acct, 0)].sub(_balances[acct]);
        else if(_circle.circleOf(acct) != 0)
            return _balancesCircle[_circle.circleOf(acct)].div(_circle.membersCount(_circle.circleOf(acct)));
    }
    function balanceSumOf(address acct) virtual public view returns (uint) {
        return balanceOf(acct).add(balanceReferOf(acct)).add(balanceCircleOf(acct));
    }
    
    function lptNetValue(uint vol) public view returns (uint) {
        CircleSwapRouter03 router = CircleSwapRouter03(_circle.router());
        address WHT = router.WETH();
        uint wht = IERC20(WHT).balanceOf(address(stakingToken));
        if(wht > 0) {
            return wht.mul(vol).div(IERC20(stakingToken).totalSupply()).mul(2);
        } else {
            uint cir = IERC20(rewardsToken).balanceOf(address(stakingToken));
            //require(cir > 0);
            cir = cir.mul(vol).div(IERC20(stakingToken).totalSupply()).mul(2);
            (uint reserve0, uint reserve1,) = IUniswapV2Pair(IUniswapV2Factory(router.factory()).getPair(WHT, address(rewardsToken))).getReserves();
            //(reserve0, reserve1) = tokenA == WHT < rewardsToken ? (reserve0, reserve1) : (reserve1, reserve0);
            return WHT < address(rewardsToken) ? cir.mul(reserve0) / reserve1 : cir.mul(reserve1) / reserve0;
        }
    }

    function increaseBalanceRefer(address referee, uint increasement) internal {
        address referer  = _circle.refererOf(referee);
        address referer2 = _circle.refererOf(referer);
        uint inc1 = increasement.mul(getConfig(_refererWeight_, 1)).div(1 ether);
        uint inc2 = increasement.mul(getConfig(_refererWeight_, 2)).div(1 ether);
        _balancesRefer[referer]  = _balancesRefer[referer ].add(inc1);
        _balancesRefer[referer2] = _balancesRefer[referer2].add(inc2);
        _totalSupplyRefer        = _totalSupplyRefer.add(inc1).add(inc2); 
    }
    
    function decreaseBalanceRefer(address referee, uint decreasement) internal {
        address referer  = _circle.refererOf(referee);
        address referer2 = _circle.refererOf(referer);
        uint dec1 = decreasement.mul(getConfig(_refererWeight_, 1)).div(1 ether);
        uint dec2 = decreasement.mul(getConfig(_refererWeight_, 2)).div(1 ether);
        _balancesRefer[referer]  = _balancesRefer[referer ].sub(dec1);
        _balancesRefer[referer2] = _balancesRefer[referer2].sub(dec2);
        _totalSupplyRefer        = _totalSupplyRefer.sub(dec1).sub(dec2); 
    }
    
    function increaseBalanceCircle(address acct, uint increasement, uint oldBalanceCircle) internal {
        if(_circle.balanceOf(acct) > 0) {
            uint id = _circle.tokenOfOwnerByIndex(acct, 0);
            _balancesCircle[id] = _balancesCircle[id].add(increasement);
        } else {
            uint id = _circle.circleOf(acct);
            if(id != 0)
                _balancesCircle[id] = _balancesCircle[id].add(increasement);
        }
        _totalSupplyCircle = _totalSupplyCircle.add(balanceCircleOf(acct)).sub(oldBalanceCircle);
    }
    
    function decreaseBalanceCircle(address acct, uint decreasement, uint oldBalanceCircle) internal {
        if(_circle.balanceOf(acct) > 0) {
            uint id = _circle.tokenOfOwnerByIndex(acct, 0);
            _balancesCircle[id] = _balancesCircle[id].sub(decreasement);
        } else {
            uint id = _circle.circleOf(acct);
            if(id != 0)
                _balancesCircle[id] = _balancesCircle[id].sub(decreasement);
        }
        _totalSupplyCircle = _totalSupplyCircle.add(balanceCircleOf(acct)).sub(oldBalanceCircle);
    }
    
    function stakeWithPermit(uint256 amount, uint deadline, uint8 v, bytes32 r, bytes32 s) virtual override public {
        require(_circle.balanceOf(msg.sender) > 0 || _circle.circleOf(msg.sender) != 0, "Not in circle");
        uint balanceCircle = balanceCircleOf(msg.sender);
        super.stakeWithPermit(amount, deadline, v, r, s);
        increaseBalanceRefer(msg.sender, amount);
        increaseBalanceCircle(msg.sender, amount, balanceCircle);
    }

    function stake(uint256 amount) virtual override public {
        require(_circle.balanceOf(msg.sender) > 0 || _circle.circleOf(msg.sender) != 0, "Not in circle");
        uint balanceCircle = balanceCircleOf(msg.sender);
        super.stake(amount);
        increaseBalanceRefer(msg.sender, amount);
        increaseBalanceCircle(msg.sender, amount, balanceCircle);
    }

    function withdraw(uint256 amount) virtual override public {
        uint balanceCircle = balanceCircleOf(msg.sender);
        super.withdraw(amount);
        decreaseBalanceRefer(msg.sender, amount);
        decreaseBalanceCircle(msg.sender, amount, balanceCircle);
    }
    
    function rewardPerToken() override public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                rewardDelta().mul(1e18).div(totalSupplySum())
            );
    }

    function earned(address account) override public view returns (uint256) {
        return balanceSumOf(account).mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(rewards[account]);
    }

    modifier updateReward(address account) virtual override {
        rewardPerTokenStored = rewardPerToken();
        rewards[address(0)] = rewards[address(0)].add(rewardDelta());
        lastUpdateTime = now;
        if (account != address(0)) {
            uint amt = rewards[account];
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;

            amt = rewards[account].sub(amt);
            address addr = address(config[_ecoAddr_]);
            uint ratio = config[_ecoRatio_];
            if(addr != address(0) && ratio != 0) {
                uint a = amt.mul(ratio).div(1 ether);
                rewards[addr] = rewards[addr].add(a);
                rewards[address(0)] = rewards[address(0)].add(a);
            }
        }
        _;
    }

}

interface ICircle is IERC721, IERC721Metadata, IERC721Enumerable {
    function router() external view returns (address);
    function refererOf(address) external view returns (address);
    function circleOf(address) external view returns (uint);
    function membersCount(uint) external view returns (uint);
}

interface CircleSwapRouter03 {
    function WETH() external pure returns (address);
    function factory() external pure returns (address);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

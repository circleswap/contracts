// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./StakingRewards.sol";
//import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/IERC721.sol";
//import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/IERC721Metadata.sol";
//import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/IERC721Enumerable.sol";
//import "./Circle.sol";

contract CirclePool is StakingPool {
    bytes32 internal constant _stakingThreshold_        = 'stakingThreshold';
    bytes32 internal constant _refererWeight_           = 'refererWeight';
    
    ICircle public circle;
    uint256 public totalSupplyRefer;
    uint256 public totalSupplyCircle;
    mapping (address => uint256) public balanceReferOf;
    mapping (uint256 => uint256) public balanceOfCircle;
    mapping (uint256 => uint256) public supplyOfCircle;
    mapping (uint256 => uint256) public rewardPerTokenStoredCircle;
    mapping (address => mapping (uint256 => uint256)) public userRewardPerTokenCircle;      // acct => tokenID => rewardPerToken
    mapping (address => uint256) public eligible;
    mapping (uint256 => uint256) public eligibleCount;

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
        circle = ICircle(circle_);
        config[_stakingThreshold_]    = 100 ether;
        _setConfig(_refererWeight_, 1, 0.25 ether);
        _setConfig(_refererWeight_, 2, 0.10 ether);
    }
    
    function amendSupplyOfCircle(uint id) external {
        uint oldSupply = supplyOfCircle[id];
        uint supply;
        for(uint i=0; i<circle.membersCount(id); i++)
            supply = supply.add(balanceCircleOf(circle.members(id, i)));
        supplyOfCircle[id] = supply;
        totalSupplyCircle = totalSupplyCircle.add(supply).sub(oldSupply);
    }

    function totalSupplySum() virtual public view returns (uint) {
        return totalSupply().add(totalSupplyRefer).add(totalSupplyCircle);
    }

    function balanceCircleOf(address acct) virtual public view returns (uint) {
        if(eligible[acct] == uint(-1) || eligible[acct] == 0 && lptNetValue(_balances[acct]) < config[_stakingThreshold_])
            return 0;
        else if(circle.balanceOf(acct) > 0)
            return balanceOfCircle[circle.tokenOfOwnerByIndex(acct, 0)].sub(_balances[acct]);
        else if(circle.circleOf(acct) != 0)
            return balanceOfCircle[circle.circleOf(acct)].div(circle.membersCount(circle.circleOf(acct)));
    }
    function balanceSumOf(address acct) virtual public view returns (uint) {
        return balanceOf(acct).add(balanceReferOf[acct]).add(balanceCircleOf(acct));
    }
    
    function lptNetValue(uint vol) public view returns (uint) {
        if(vol == 0)
            return 0;
        CircleSwapRouter03 router = CircleSwapRouter03(circle.router());
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

    function _updateEligible(address acct) internal {
        uint oldEligible = eligible[acct];
        eligible[acct] = lptNetValue(_balances[acct]) >= config[_stakingThreshold_] ? 1 : uint(-1);
        uint id = circle.circleOf(acct);
        if(id != 0) {
            if(oldEligible != 1 && eligible[acct] == 1)
                eligibleCount[id] = eligibleCount[id].add(1);
            else if(oldEligible == 1 && eligible[acct] == uint(-1))
                eligibleCount[id] = eligibleCount[id].sub(1);
        }
    }
    
    function _increaseBalanceRefer(address referee, uint increasement) internal {
        address referer  = circle.refererOf(referee);
        address referer2 = circle.refererOf(referer);
        uint inc1 = circleOf(referer)  != 0 ? increasement.mul(getConfig(_refererWeight_, 1)).div(1 ether) : 0;
        uint inc2 = circleOf(referer2) != 0 ? increasement.mul(getConfig(_refererWeight_, 2)).div(1 ether) : 0;
        balanceReferOf[referer]  = balanceReferOf[referer ].add(inc1);
        balanceReferOf[referer2] = balanceReferOf[referer2].add(inc2);
        totalSupplyRefer        = totalSupplyRefer.add(inc1).add(inc2); 
    }
    
    function _decreaseBalanceRefer(address referee, uint decreasement) internal {
        address referer  = circle.refererOf(referee);
        address referer2 = circle.refererOf(referer);
        uint dec1 = circleOf(referer)   != 0 ? decreasement.mul(getConfig(_refererWeight_, 1)).div(1 ether) : 0;
        uint dec2 = circleOf(referer2)  != 0 ? decreasement.mul(getConfig(_refererWeight_, 2)).div(1 ether) : 0;
        balanceReferOf[referer]  = balanceReferOf[referer ].sub(dec1);
        balanceReferOf[referer2] = balanceReferOf[referer2].sub(dec2);
        totalSupplyRefer        = totalSupplyRefer.sub(dec1).sub(dec2); 
    }
    
    function _increaseBalanceCircle(address acct, uint increasement, uint oldBalanceCircle) internal {
        uint id = circleOf(acct);
        if(id == 0)
            return;
        balanceOfCircle[id] = balanceOfCircle[id].add(increasement);
        uint newBalanceCircle = balanceCircleOf(acct);
        uint delta = _deltaSupplyCircle(id, acct, increasement).add(newBalanceCircle).sub(oldBalanceCircle);
        supplyOfCircle[id] = supplyOfCircle[id].add(delta);
        totalSupplyCircle = totalSupplyCircle.add(delta);
    }
    
    function _decreaseBalanceCircle(address acct, uint decreasement, uint oldBalanceCircle) internal {
        uint id = circleOf(acct);
        if(id == 0)
            return;
        balanceOfCircle[id] = balanceOfCircle[id].sub(decreasement);
        uint newBalanceCircle = balanceCircleOf(acct);
        uint delta = _deltaSupplyCircle(id, acct, decreasement).add(oldBalanceCircle).sub(newBalanceCircle);
        supplyOfCircle[id] = supplyOfCircle[id].sub(delta);
        totalSupplyCircle = totalSupplyCircle.sub(delta);
    }
    
    function _deltaSupplyCircle(uint id, address acct, uint deltaBalance) internal view returns (uint delta) {
        delta = deltaBalance.mul(eligibleCount[id]).div(circle.membersCount(id));
        if(circle.circleOf(acct) != 0) {
            if(eligible[acct] == 1)
                delta = delta.sub(deltaBalance.div(circle.membersCount(id)));
            if(eligible[circle.ownerOf(id)] == 1)
                delta = delta.add(deltaBalance);
        }
    }
    
    function circleOf(address acct) public view returns (uint id) {
        id = circle.circleOf(acct);
        if(id == 0 && circle.balanceOf(acct) > 0)
            id = circle.tokenOfOwnerByIndex(acct, 0);
    }
    
    function stakeWithPermit(uint256 amount, uint deadline, uint8 v, bytes32 r, bytes32 s) virtual override public {
        require(circleOf(msg.sender) != 0, "Not in circle");
        uint balanceCircle = balanceCircleOf(msg.sender);
        super.stakeWithPermit(amount, deadline, v, r, s);
        _updateEligible(msg.sender);
        _increaseBalanceRefer(msg.sender, amount);
        _increaseBalanceCircle(msg.sender, amount, balanceCircle);
    }

    function stake(uint256 amount) virtual override public {
        require(circleOf(msg.sender) != 0, "Not in circle");
        uint balanceCircle = balanceCircleOf(msg.sender);
        super.stake(amount);
        _updateEligible(msg.sender);
        _increaseBalanceRefer(msg.sender, amount);
        _increaseBalanceCircle(msg.sender, amount, balanceCircle);
    }

    function withdraw(uint256 amount) virtual override public {
        uint balanceCircle = balanceCircleOf(msg.sender);
        super.withdraw(amount);
        _updateEligible(msg.sender);
        _decreaseBalanceRefer(msg.sender, amount);
        _decreaseBalanceCircle(msg.sender, amount, balanceCircle);
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

    function rewardPerTokenCircle(uint id) virtual public view returns (uint) {
        if (supplyOfCircle[id] == 0) {
            return rewardPerTokenStoredCircle[id];
        }
        return
            rewardPerTokenStoredCircle[id].add(
                rewardDeltaCircle(id).mul(1e18).div(supplyOfCircle[id])
            );
    }
    
    function rewardDeltaCircle(uint id) virtual public view returns (uint) {
        return supplyOfCircle[id].mul(rewardPerToken().sub(userRewardPerTokenPaid[address(id)])).div(1e18);
    }

    function earned(address acct) override public view returns (uint256) {
        uint id = circleOf(acct);
        return balanceCircleOf(acct).mul(rewardPerTokenCircle(id).sub(userRewardPerTokenCircle[acct][id])).div(1e18).add(
            balanceOf(acct).add(balanceReferOf[acct]).mul(rewardPerToken().sub(userRewardPerTokenPaid[acct])).div(1e18).add(rewards[acct]));
    }

    modifier updateReward(address acct) virtual override {
        (uint delta, uint d) = (rewardDelta(), 0);

        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = now;
        if (acct != address(0)) {
            if(eligible[acct] == 0)
                _updateEligible(acct);
            
            _updateReward(acct);
        
            uint id = circleOf(acct);
            if(id != 0) {
                userRewardPerTokenCircle[acct][id] = rewardPerTokenStoredCircle[id] = rewardPerTokenCircle(id);
                userRewardPerTokenPaid[address(id)] = rewardPerTokenStored;
            }
            
            _updateReward(acct = circle.refererOf(acct));
            _updateReward(circle.refererOf(acct));
        }

        address addr = address(config[_ecoAddr_]);
        uint ratio = config[_ecoRatio_];
        if(addr != address(0) && ratio != 0) {
            d = delta.mul(ratio).div(1 ether);
            rewards[addr] = rewards[addr].add(d);
        }
        rewards[address(0)] = rewards[address(0)].add(delta).add(d);

        _;
    }
    
    function _updateReward(address acct) virtual internal {
        rewards[acct] = earned(acct);
        userRewardPerTokenPaid[acct] = rewardPerTokenStored;
    }
    
}

interface ICircle {         // is IERC721, IERC721Metadata, IERC721Enumerable {
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function balanceOf(address owner) external view returns (uint256 balance);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256 tokenId);

    function router() external view returns (address);
    function refererOf(address) external view returns (address);
    function circleOf(address) external view returns (uint);
    function members(uint256 tokenID, uint i) external view returns (address);
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

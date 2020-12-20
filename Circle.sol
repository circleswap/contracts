// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
//pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/Math.sol";
import "./Governable.sol";
//import "./Relation.sol";

contract Circle is ERC721UpgradeSafe, Configurable {
    using EnumerableSet for EnumerableSet.AddressSet;

    address constant BurnAddress                            = 0x000000000000000000000000000000000000dEaD;
    bytes32 internal constant _swapAmountThreshold_         = 'swapAmountThreshold';
    bytes32 internal constant _capacity_                    = 'capacity';
    bytes32 internal constant _burnTicket_                  = 'burnTicket';
    bytes32 internal constant _airdropWeight_               = 'airdropWeight';
    bytes32 internal constant _airdropWeightMaxN_           = 'airdropWeightMaxN';

    mapping (uint => uint) public levelOf;                  // tokenID => level
    mapping (uint => EnumerableSet.AddressSet) internal _members;     // tokenID => members;
    mapping (address => uint) public circleOf;              // acct => tokenID
    mapping (address => address) public refererOf;          // acct => referer;
    
    address public CIR;
    //address public relation;
    address public router;
    uint public nextID;
    
    mapping (address => uint) public refereeN;
    mapping (address => uint) public referee2N;
    
    uint totalAirdropWeight;
    
    function __Circle_init(address governor_, string memory name, string memory symbol, address CIR_, address router_) public initializer {
        Governable.initialize(governor_);
        __Context_init_unchained();
        __ERC165_init_unchained();
        __ERC721_init_unchained(name, symbol);
        __Circle_init_unchained(CIR_, router_);
    }
    
    function __Circle_init_unchained(address CIR_, address router_) public governance {
        CIR = CIR_;
        //relation = relation_;
        router = router_;
        nextID = 10;
        config[_swapAmountThreshold_] = 100 ether;
        _setConfig(_capacity_,   1,   30);
        _setConfig(_capacity_,   2,  200);
        _setConfig(_capacity_,   3,  500);
        _setConfig(_burnTicket_, 0,    2 ether);
        _setConfig(_burnTicket_, 1,  100 ether);
        _setConfig(_burnTicket_, 2,  500 ether);
        _setConfig(_burnTicket_, 3, 1000 ether);
        _setConfig(_airdropWeight_, 1, 0.3 ether);
        _setConfig(_airdropWeight_, 2, 0.1 ether);
        _setConfig(_airdropWeightMaxN_, 1,  5);
        _setConfig(_airdropWeightMaxN_, 2, 25);

        refererOf[_msgSender()] = _msgSender();
    }
    
    function bind(address referer) virtual public {
        require(refererOf[_msgSender()] == address(0), 'Already binded');
        require(refererOf[referer] != address(0), 'referer has not binded yet');
        require(referer != _msgSender() && refererOf[referer] != _msgSender() && refererOf[refererOf[referer]] != _msgSender(), 'No bind cyclic');
        refererOf[_msgSender()] = referer;
        
        uint airdropWeight2 = airdropWeight(referer).add(airdropWeight(refererOf[referer]));
        refereeN[referer] = refereeN[referer].add(1);
        referee2N[refererOf[referer]] = referee2N[refererOf[referer]].add(1);
        totalAirdropWeight = totalAirdropWeight.add(airdropWeight(referer)).add(airdropWeight(refererOf[referer])).sub(airdropWeight2);
        emit Bind(_msgSender(), referer, refererOf[referer]);
    }
    event Bind(address indexed referee, address indexed referer, address indexed referer2);
    
    function airdropWeight(address acct) public view returns (uint) {
        return uint(1 ether).add(getConfig(_airdropWeight_, 1).mul(Math.min(getConfig(_airdropWeightMaxN_, 1), refereeN[acct]))).add(getConfig(_airdropWeight_, 2).mul(Math.min(getConfig(_airdropWeightMaxN_, 2), referee2N[acct])));
    }

    function eligible(address acct) public view virtual returns (bool) {
        return refererOf[acct] != address(0) && CircleSwapRouter03(router).swapAmountOf(acct) >= config[_swapAmountThreshold_];
    }
    
    function capacity(uint level) public view virtual returns (uint) {
        return getConfig(_capacity_, level);
    }
    
    function checkQualification(address acct) internal view virtual {
        require(eligible(acct), 'ineligible');
        require(balanceOf(acct) == 0, 'already owned circle');
        require(circleOf[acct] == 0, 'already joined circle');
    }

    function _beforeTokenTransfer(address, address to, uint256) internal virtual override {
        checkQualification(to);
    }
    
    function mint(string memory name, uint level) external virtual {
        checkQualification(_msgSender());
        require(getConfig(_burnTicket_, level) > 0, 'unsupported level');
        
        IERC20(CIR).transferFrom(_msgSender(), BurnAddress, getConfig(_burnTicket_, level));
        levelOf[nextID] = level;
        _mint(_msgSender(), nextID);
        _setTokenURI(nextID, name);
        emit Mint(_msgSender(), nextID, name, level);
        nextID++;
    }
    event Mint(address acct, uint tokenID, string name, uint level);
    
    function join(uint tokenID) external virtual {
        checkQualification(_msgSender());
        require(_members[tokenID].length() < getConfig(_capacity_, levelOf[tokenID]), 'circle capacity overflow');

        IERC20(CIR).transferFrom(_msgSender(), BurnAddress, getConfig(_burnTicket_, 0));
        _members[tokenID].add(_msgSender());
        circleOf[_msgSender()] = tokenID;
        emit Join(_msgSender(), tokenID, ownerOf(tokenID), _members[tokenID].length());
    }
    event Join(address acct, uint tokenID, address owner, uint count);
    
    function membersCount(uint256 tokenID) public view returns (uint) {
        return _members[tokenID].length();
    }
    
    function members(uint256 tokenID, uint i) public view returns (address) {
        return _members[tokenID].at(i);
    }

    uint256[50] private __gap;
}


interface CircleSwapRouter03 {
    function swapAmountOf(address acct) external view returns (uint);
}

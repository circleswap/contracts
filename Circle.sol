// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
//pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "./Governable.sol";
//import "./Relation.sol";

contract Circle is ERC721UpgradeSafe, Configurable {
    using EnumerableSet for EnumerableSet.AddressSet;

    address constant BurnAddress                            = 0x000000000000000000000000000000000000dEaD;
    bytes32 internal constant _swapAmountThreshold_         = 'swapAmountThreshold';
    bytes32 internal constant _capacity_                    = 'capacity';
    bytes32 internal constant _burnTicket_                  = 'burnTicket';
    
    mapping (uint => uint) public levelOf;                  // tokenID => level
    mapping (uint => EnumerableSet.AddressSet) internal _members;     // tokenID => members;
    mapping (address => uint) public circleOf;              // acct => tokenID
    mapping (address => address) public refererOf;          // acct => referer;
    
    address public CIR;
    //address public relation;
    address public router;
    uint public nextID;
    
    function __Circle_init(string memory name, string memory symbol, address CIR_, address router_) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __ERC721_init_unchained(name, symbol);
        __Circle_init_unchained(CIR_, router_);
    }
    
    function __Circle_init_unchained(address CIR_, address router_) internal initializer {
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

        refererOf[_msgSender()] = _msgSender();
    }
    
    function bind(address referer) virtual public {
        require(refererOf[_msgSender()] == address(0), 'Already binded');
        require(refererOf[referer] != address(0), 'referer has not binded yet');
        require(referer != _msgSender() && refererOf[referer] != _msgSender() && refererOf[refererOf[referer]] != _msgSender(), 'No bind cyclic');
        refererOf[_msgSender()] = referer;
        emit Bind(_msgSender(), referer);
    }
    event Bind(address referee, address referer);

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
    
    function mint(uint level) external virtual {
        checkQualification(_msgSender());
        require(getConfig(_burnTicket_, level) > 0, 'unsupported level');
        
        IERC20(CIR).transferFrom(_msgSender(), BurnAddress, getConfig(_burnTicket_, level));
        levelOf[nextID] = level;
        _mint(_msgSender(), nextID);
        nextID++;
    }
    
    function join(uint tokenID) external virtual {
        checkQualification(_msgSender());
        require(_members[tokenID].length() < getConfig(_capacity_, levelOf[tokenID]), 'circle capacity overflow');

        IERC20(CIR).transferFrom(_msgSender(), BurnAddress, getConfig(_burnTicket_, 0));
        _members[tokenID].add(_msgSender());
        circleOf[_msgSender()] = tokenID;
    }
    
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

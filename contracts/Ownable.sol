// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Ownable
 * @dev Contract module which provides basic authorization control
 */
contract Ownable {
    address private _owner;
    
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    
    constructor() {
        _transferOwnership(msg.sender);
    }
    
    modifier onlyOwner() {
        _checkOwner();
        _;
    }
    
    function owner() public view returns (address) {
        return _owner;
    }
    
    function _checkOwner() internal view {
        if(msg.sender != _owner) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
    }
    
    function transferOwnership(address newOwner) public onlyOwner {
        if(newOwner == address(0)) {
            revert OwnableInvalidOwner(newOwner);
        }
        _transferOwnership(newOwner);
    }
    
    function _transferOwnership(address newOwner) internal {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}
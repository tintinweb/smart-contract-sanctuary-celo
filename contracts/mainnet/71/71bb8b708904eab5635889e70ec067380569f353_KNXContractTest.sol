// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface iKNX {
    function walletOfOwner(address _owner) external view returns (uint256[] memory);
    function balanceOf(address account) external view returns (uint256);
    function owner() external view returns(address);
}

contract KNXContractTest {
    address private KNXaddress = 0xa81D9a2d29373777E4082d588958678a6Df5645c;
    uint256 public productIndex = 1;

    function checkKNXOwner() public view returns (address) {
        address owner = iKNX(KNXaddress).owner();
        return owner;
    }

    function checkKNXBalanceOf(address _address) public view returns (uint256) {
        uint256 token = iKNX(KNXaddress).balanceOf(_address);
        return token;
    }

    function checkKNXWalletOwner() public view returns (uint256[] memory) {
        uint256[] memory wallets = iKNX(KNXaddress).walletOfOwner(msg.sender);
        return wallets;
    }
}
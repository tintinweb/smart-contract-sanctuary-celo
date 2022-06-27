// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract CELODisperse {
  address payable recipient;
  address payable admin;
  uint256 iFee = 3000000000000000000;

  constructor() public {
    admin = msg.sender;
  }

  function disperseEther(address[] memory recipients, uint256[] memory values) external payable {
    admin.transfer(iFee);
    for (uint256 i = 0; i < recipients.length; i++) {
       recipient = payable(recipients[i]);
       recipient.transfer(values[i]);
     }
     uint256 balance = address(this).balance;
     if (balance > 0) {
       msg.sender.transfer(balance);
     }

    }

    function setFee(uint256 newFee) public {
      require(msg.sender == admin, "ALERT:Only Admin can set new Fee");
      iFee = newFee;
    }

    function disperseToken(IERC20 token, address[] memory recipients, uint256[] memory values) external payable {
      admin.transfer(iFee);
      uint256 total = 0;
      for (uint256 i = 0; i < recipients.length; i++)
        total += values[i];
      require(token.transferFrom(msg.sender, address(this), total));
      for (uint256 i = 0; i < recipients.length; i++)
        require(token.transfer(address(recipients[i]), values[i]));
    }

    function disperseTokenSimple(IERC20 token, address[] memory recipients, uint256[] memory values) external payable {
      admin.transfer(iFee);
      for (uint256 i = 0; i < recipients.length; i++)
        require(token.transferFrom(msg.sender, recipients[i], values[i]));
    }
}
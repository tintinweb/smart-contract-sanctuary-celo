// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract VIP {
  mapping(address => bool) public invited;

  event Invited(address indexed guest, address indexed by);
  
  constructor() {
    invited[msg.sender] = true;
  }

  function invite(address _guest) external {
    require(invited[msg.sender], "Uninvited guest inviting another uninvited guest");
    invited[_guest] = true;
    emit Invited(_guest, msg.sender);
  }

  function batchInvite(address[] memory _guests) external {
    require(invited[msg.sender], "Uninvited guest inviting another uninvited guest");
    uint256 length = _guests.length;
    for (uint i = 0; i < length; i++) {
      address guest = _guests[i];
      invited[guest] = true;
      emit Invited(guest, msg.sender);
    }
  }
}
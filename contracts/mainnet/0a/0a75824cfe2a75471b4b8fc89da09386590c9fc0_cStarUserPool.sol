// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;

contract cStarUserPool {
   address addrAdmin;
   address addrDev;

   enum UserLevel { Ace, King, Jack, Guard }

   struct UserInfo {
      address addrUser;
      uint256 balanceStaked;
      UserLevel userLevel;
      uint256 iStartTime;
   }

   address[] addrsAces;
   uint256[] iAcesStartTime;
   address[] addrsKings;
   uint256[] iKingsStartTime;
   address[] addrsJacks;
   uint256[] iJacksStartTime;
   address[] addrsGuards;
   uint256[] iGuardsStartTime;

   mapping (address => UserInfo) mapUser;

   modifier _needsAdmin() {
      require(msg.sender == addrDev || msg.sender == addrAdmin, "ALERT: Admin or Dev need to set");

      _;
   }

   constructor() public {
      addrDev = msg.sender;
   }

   function setAdmin(address addr) public _needsAdmin() {
      addrAdmin = addr;
   }

   function addUser(address account, uint256 amount) external returns (bool) {
      this.removeUser(account);
      
      if(amount > 9999999999999999999999 && amount < 24999999999999999999999) {
         UserInfo memory newUser = UserInfo(account, amount,UserLevel.Guard, block.timestamp);
         mapUser[account] = newUser;
         addrsGuards.push(account);
         iGuardsStartTime.push(block.timestamp);
      } else if(amount > 24999999999999999999999 && amount < 124999999999999999999999) {
         UserInfo memory newUser = UserInfo(account, amount, UserLevel.Jack, block.timestamp);
         mapUser[account] = newUser;
         addrsJacks.push(account);
         iJacksStartTime.push(block.timestamp);
      } else if(amount > 124999999999999999999999 && amount < 249999999999999999999999) {
         UserInfo memory newUser = UserInfo(account, amount, UserLevel.King, block.timestamp);
         mapUser[account] = newUser;
         addrsKings.push(account);
         iKingsStartTime.push(block.timestamp);
      } else if(amount > 249999999999999999999999) {
         UserInfo memory newUser = UserInfo(account, amount, UserLevel.Ace, block.timestamp);
         mapUser[account] = newUser;
         addrsAces.push(account);
         iAcesStartTime.push(block.timestamp);
      }

      return true;
   }

   function removeUser(address account) external {
      UserInfo memory editUser = mapUser[account];

      if(editUser.userLevel == UserLevel.Guard) {
         for(uint i = 0; i < addrsGuards.length; i++) {
            if(addrsGuards[i] == account) {
               if(i == addrsGuards.length-1) {
                  addrsGuards.pop();
                  iGuardsStartTime.pop();
               } else {
                  addrsGuards[i] = addrsGuards[addrsGuards.length-1];
                  iGuardsStartTime[i] = iGuardsStartTime[iGuardsStartTime.length-1];
                  addrsGuards.pop();
                  iGuardsStartTime.pop();
               }
            }
         }
      } else if(editUser.userLevel == UserLevel.Jack) {
         for(uint i = 0; i < addrsJacks.length; i++) {
            if(addrsJacks[i] == account) {
               if(i == addrsJacks.length-1) {
                  addrsJacks.pop();
                  iJacksStartTime.pop();
               } else {
                  addrsJacks[i] = addrsJacks[addrsJacks.length-1];
                  iJacksStartTime[i] = iJacksStartTime[iJacksStartTime.length-1];
                  addrsJacks.pop();
                  iJacksStartTime.pop();
               }
            }
         }
      } else if(editUser.userLevel == UserLevel.King) {
         for(uint i = 0; i < addrsKings.length; i++) {
            if(addrsKings[i] == account) {
               if(i == addrsKings.length-1) {
                  addrsKings.pop();
                  iKingsStartTime.pop();
               } else {
                  addrsKings[i] = addrsKings[addrsKings.length-1];
                  iKingsStartTime[i] = iKingsStartTime[iKingsStartTime.length-1];
                  addrsKings.pop();
                  iKingsStartTime.pop();
               }
            }
         }
      } else if(editUser.userLevel == UserLevel.Ace) {
         for(uint i = 0; i < addrsAces.length; i++) {
            if(addrsAces[i] == account) {
               if(i == addrsAces.length-1) {
                  addrsAces.pop();
                  iAcesStartTime.pop();
               } else {
                  addrsAces[i] = addrsAces[addrsAces.length-1];
                  iAcesStartTime[i] = iAcesStartTime[iAcesStartTime.length-1];
                  addrsAces.pop();
                  iAcesStartTime.pop();
               }
            }
         }
      }

      delete mapUser[account];
   }

   function getAces() external view returns (address[] memory, uint256[] memory) {
      return (addrsAces, iAcesStartTime);
   }

   function getKings() external view returns (address[] memory, uint256[] memory) {
      return (addrsKings, iKingsStartTime);
   }

   function getJacks() external view returns (address[] memory, uint256[] memory) {
      return (addrsJacks, iJacksStartTime);
   }

   function getGuards() external view returns (address[] memory, uint256[] memory) {
      return (addrsGuards, iGuardsStartTime);
   }
}
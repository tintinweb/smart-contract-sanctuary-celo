// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IERC20 {
   function transfer(address to, uint256 value) external returns (bool);
   function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IPXLShareRouter {
   function swapNative() payable external;
   function payWithSupportedToken(address _intoken, uint256 _amount) external;
}

contract PXLDisperse {
   address payable recipient;
   address payable addrDev;
   IPXLShareRouter router;
   uint256 iFee = 1 ether;

   constructor(IPXLShareRouter _router) {
      addrDev = payable(msg.sender);
      router = _router;
   }

   modifier _onlyDev() {
      require(msg.sender == addrDev, "ALERT: Your are not dev!");

      _;
   }

   modifier _paymentNeeded() {
      if(msg.sender != addrDev) {
         require(msg.value == iFee, "ALERT: incorrect payment!");

         router.swapNative{value: iFee}();
      }

      _;
   }

   function setAdmin(address _dev) public _onlyDev() {
      addrDev = payable(_dev);
   }

   function setRouter(IPXLShareRouter _router) public _onlyDev() {
      router = _router;
   }

   function setFee(uint256 newFee) public _onlyDev() {
      iFee = newFee;
   }

   function disperseNative(address[] memory recipients, uint256[] memory values) public payable _paymentNeeded() {
      for (uint256 i = 0; i < recipients.length; i++) {
         recipient = payable(recipients[i]);
         recipient.transfer(values[i]);
      }

      uint256 balance = address(this).balance;

      if (balance > 0) {
         address payable sender = payable(msg.sender);
         sender.transfer(balance);
      }
   }

   function disperseToken(IERC20 token, address[] memory recipients, uint256[] memory values) public payable  _paymentNeeded() {
      uint256 total = 0;
      for (uint256 i = 0; i < recipients.length; i++)
         total += values[i];
      require(token.transferFrom(msg.sender, address(this), total));
      for (uint256 i = 0; i < recipients.length; i++)
         require(token.transfer(address(recipients[i]), values[i]));
   }

   function disperseTokenSimple(IERC20 token, address[] memory recipients, uint256[] memory values) external payable  _paymentNeeded() {
      for (uint256 i = 0; i < recipients.length; i++)
        require(token.transferFrom(msg.sender, recipients[i], values[i]));
   }

   function recoverERC20(address tokenAddress, uint256 tokenAmount) public _onlyDev() {
      IERC20(tokenAddress).transfer(addrDev, tokenAmount);
      emit Recovered(tokenAddress, tokenAmount);
   }

   event Recovered(address token, uint256 amount);
}
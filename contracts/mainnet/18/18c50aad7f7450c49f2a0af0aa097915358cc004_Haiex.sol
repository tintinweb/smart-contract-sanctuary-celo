// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

interface IERC20 {

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function deposit(address to, uint256 amount) external returns (bool);
    function withdraw(address from, uint256 amount) external returns (bool);
    function sendTo(address sender, address recipient, uint256 amount) external returns (bool);


    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract Router {

  function swapExactTokensForTokens(
    uint amountIn,
    uint amountOutMin,
    address[] calldata path,
    address to,
    uint deadline
  ) external returns (uint[] memory amounts)  {}

  function getAmountsOut(uint amountIn, address[] memory path) public view returns (uint[] memory amounts){}

  function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts){}
  
  function WETH() external pure returns (address){}
}

contract Haiex  {
    
    Router private  router = Router(0xE3D8bd6Aed4F159bc8000a9cD47CffDb95F96121);
    address private  WETH = 0x471EcE3750Da237f93B8E339c536989b8978a438;

    IERC20 HTGToken ;
    IERC20 USDToken ;

    uint256 public price;

    uint256 public  fees; 

    address public  owner;
    address public  admin;
    address public  manager;

    bool pause = false;

 
    constructor(uint256 inittialPrice_, address usdToken, address htgToken)   {  
        owner = msg.sender;
        admin = msg.sender;
        manager = msg.sender;

        fees =  70; //=> 50/100 = 0.7%

        price = inittialPrice_;
        USDToken = IERC20(usdToken);
        HTGToken = IERC20(htgToken);
    }  

    /// Modifies a function to only run if sent by `role` or the contract's `owner`.
    modifier onlyOwner() {
        require(msg.sender == owner, "unauthorized: not owner");
        _;
    }

    modifier onlyManager() {
        require(msg.sender == manager, "unauthorized: not manager");
        _;
    }

    modifier onlyManagerOrOwner() {
        require(msg.sender == manager||msg.sender == owner, "unauthorized: not owner or manager");
        _;
    }

     modifier isOnPause() {
        require(pause==false, "Services on pause for maintenance");
        _;
    }

    function changeRouter(address routerAddr) public onlyOwner returns (bool) {
        router = Router(routerAddr);
        return true;
    }

    function changeWETH(address wethAddr) public onlyOwner returns (bool) {
        WETH = wethAddr;
        return true;
    }

    function changeUSD(address usdToken) public onlyManagerOrOwner returns (bool) {
        USDToken = IERC20(usdToken);
        return true;
    }

    function changeHTG(address htgToken) public onlyManagerOrOwner returns (bool) {
        HTGToken = IERC20(htgToken);
        return true;
    }

    function changeFee(uint256 fee_) public onlyManagerOrOwner returns (bool) {
        require(msg.sender == owner, "Only owner can set the fee");
        fees = fee_;
        return true;
    }

    function changePriceSOS(uint256 pricce_) public onlyManagerOrOwner returns (bool) {
        price = pricce_;
        return true;
    }

    function changeAdmin(address admin_) public onlyOwner returns (bool) {
        require(admin_ != address(0) , "Collector can't be null");
        admin = admin_;
        return true;
    }

    function changeOwner(address owner_) public onlyOwner returns (bool) {
        require(owner_ != address(0) , "Owner can't be null");
        owner = owner_;
        return true;
    }

    function changeManager(address manager_) public onlyOwner returns (bool) {
        require(manager_ != address(0) , "Manager can't be null");
        manager = manager_;
        return true;
    }

    function setPausable(bool pause_) public onlyOwner returns (bool) {
        pause = pause_;
        return true;
    }


    function buyHTG(uint256 usd) public  isOnPause returns (bool) {
        
        require(usd > 0, "Usd amount can't be zero");
        require(USDToken.balanceOf(msg.sender) >= usd, "Token not enough");
        require(USDToken.allowance(msg.sender, address(this)) >= usd, "Allowance not enough");
        require(price > 0, "Price has not been define");


        uint256 taxes  = div(mul(usd,fees), 10**4); 
        uint256 usdTaxed = usd - taxes;
        uint256 tokens = div(mul(usdTaxed, price), 1000);

        USDToken.transferFrom(msg.sender, address(this), usdTaxed + (taxes/2));
        USDToken.transferFrom(msg.sender, admin, taxes/2);

        
        HTGToken.deposit(address(this), tokens);
        HTGToken.transfer(msg.sender, tokens);

        return true;
    }


    function sellHTG(uint256 tokens) public isOnPause returns (bool) {

        require(tokens > 0, "Usd amount can't be zero");
        require(HTGToken.balanceOf(msg.sender) >= tokens, "Token not enough");
        require(HTGToken.allowance(msg.sender, address(this)) >= tokens, "Allowance not enough");

        require(price > 0, "Price has not been define");


        uint256 usd = mul(div(tokens, price), 1000);
        uint256 taxes  = div(mul(usd,fees), 10**4); 
        uint256 usdTaxed = usd - taxes;

        HTGToken.transferFrom(msg.sender, address(this), tokens);
        HTGToken.withdraw(address(this), tokens);

        USDToken.transfer(msg.sender, usdTaxed);
        USDToken.transfer(admin, taxes/2);

        return true;
    }


    function sendHTG(address from, address to,  uint256 tokens) public isOnPause returns (bool) {

        require(tokens > 0, "Tokens amount can't be zero");
        require(to != address(0), "Recipient can't be null address");
        require(HTGToken.balanceOf(msg.sender) >= tokens, "Token not enough");
        HTGToken.sendTo(from, to , tokens);

        return true;
    }


    function swap(address tok_in,address tok_out, address[] memory path,  uint256 amount) public isOnPause
    {

        IERC20 token1  = IERC20(tok_in);
        IERC20 token2  = IERC20(tok_out);


        require(amount > 0, "Usd amount can't be zero");
        require(token1.balanceOf(msg.sender) >= amount, "Token not enough");
        require(token1.allowance(msg.sender, address(this)) >= amount, "Allowance not enough");  
        require(price > 0, "Price has not been define");
        require(tok_in != tok_out, "Can't swap same tokens");

       

        // uint usdAmount = amount;

        if( HTGToken == token1){
               
                
            uint256 usd = mul(div(amount, price), 1000); // Convert htg to usd
            uint256 taxes  = div(mul(usd,fees), 10**4);  // calculate fees
            uint256 usdTaxed = usd - taxes; // remove fees total amount

            USDToken.transfer(admin, taxes/2); //Send a part of the fee to admin and leave the for liquidity

            //Get sender TGOUD and Burn them tokens 
            HTGToken.transferFrom(msg.sender, address(this), amount);
            HTGToken.withdraw(address(this), amount);

            //Allow Quickswap to use the amount of usd
            USDToken.approve(address(router), usdTaxed);

            //Swap the USD to token
            router.swapExactTokensForTokens(
            usdTaxed,
            0,
            path,
            msg.sender,
            block.timestamp
            );

        }
        else if( HTGToken == token2){
              
            token1.transferFrom(
            msg.sender,
            address(this),
            amount
            );


            //Allow Quickswap to use the amount of usd
            token1.approve(address(router), amount);

            //Swap the USD to token
             uint[] memory  amounts = router.swapExactTokensForTokens(
            amount,
            0,
            path,
            address(this),
            block.timestamp
            );

            uint amountOut = amounts[amounts.length-1];
            uint256 taxes  = div(mul(amountOut,fees), 10**4); 
            uint256 usdTaxed = amountOut - taxes;
            uint256 tokens = div(mul(usdTaxed, price), 1000);

            HTGToken.deposit(address(this), tokens);
            HTGToken.transfer(msg.sender, tokens);

        }
        else{
            //Transfer token1 to the smart Contract
            token1.transferFrom(
            msg.sender,
            address(this),
            amount
            );

         

            //Allow Quickswap to use the amount of usd
            token1.approve(address(router), amount);

            //Swap the USD to token
            router.swapExactTokensForTokens(
            amount,
            0,
            path,
            msg.sender,
            block.timestamp
            );
        }
       
    }

   function amountsOut(address[] memory path,  uint amount) public view returns(uint[] memory amounts)
    {

                return router.getAmountsOut(amount, path);
    }

   function getUSDReserve() public view  returns(uint256){
        return USDToken.balanceOf(address(this));
    }

    function getHTGReserve() public view returns(uint256){
        return HTGToken.totalSupply();
    }

    function emergencyWithdraw(address recipient) public onlyOwner  returns(bool){
       uint256 balance = USDToken.balanceOf(address(this));
       USDToken.transfer(recipient, balance);
       return true;
    }





    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
      assert(b <= a);
      return a - b;
    }
    
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
      uint256 c = a + b;
      assert(c >= a);
      return c;
    }

    function mul(uint256 a, uint256 b) public pure returns (uint256 ) {
        uint256 c = a * b;
        
        assert(a == 0 || c / a == b);
            return c;
    }

    function div(uint256 a, uint256 b) public pure returns (uint256 ) {
        assert(b > 0);
        uint256	c = a / b;
        return c;
    }
}
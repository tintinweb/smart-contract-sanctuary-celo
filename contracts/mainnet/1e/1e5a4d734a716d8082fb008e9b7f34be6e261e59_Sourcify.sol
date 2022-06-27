pragma solidity 0.6.12;

library Lib {
    function one() external pure returns(uint) {
        return 10;
    }
}

library Lib2 {
    function two() external pure returns(uint) {
        return 20 + Lib.one();
    }
}

contract Sourcify {
    function lib() external pure returns(uint) {
        return Lib.one() + Lib2.two();
    }

    function lib2() external pure returns(uint) {
        return Lib2.two() + Lib.one();
    }
}
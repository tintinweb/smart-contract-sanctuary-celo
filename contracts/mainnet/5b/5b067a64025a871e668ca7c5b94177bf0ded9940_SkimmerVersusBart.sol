pragma solidity ^0.7.0;

interface skimInterface {
	function skim(address to) external;
}

contract SkimmerVersusBart {
	address[] public lpsToSkim;
	address skimmer = 0x786798aDDD58507B3F9466a1365242868Cd96A5B;
	mapping (address => bool) lpexists;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('skim(address)')));


	constructor(address[] memory _lps) {
		lpsToSkim = _lps;
	}

	function changeSkimmer(address to) public {
		require(msg.sender == skimmer);
		skimmer = to;
	}
	
	function addlps(address[] memory lps) public {
	   require(msg.sender == 0x3f119Cef08480751c47a6f59Af1AD2f90b319d44, "Reserved function");
		uint256 i = 0;
		address lp;
		while (i < lps.length) {
			lp = lps[i];
			if (!lpexists[lp]) {
				lpsToSkim.push(lp);
				lpexists[lp] = true;
			}
			i += 1;
		}
	}
	
	function _skim(address token, address to) private returns (bool) {
        (bool success, ) = token.call(abi.encodeWithSelector(SELECTOR, to));
        return success;
    }
	
	function skim(address to) public {
		require(msg.sender == skimmer);
		uint256 i = 0;
		bool success;
		while (i < lpsToSkim.length) {
			success = (_skim(lpsToSkim[i],to) || success);
			i += 1;
		}
		require(success, "None of txs succeeded, reverting");
	}
}
pragma solidity ^0.7.0;

interface skimInterface {
	function skim(address to) external;
}

contract PrincipalSkimmer {
	address[] public lpsToSkim;
	address skimmer = 0x786798aDDD58507B3F9466a1365242868Cd96A5B;
	mapping (address => bool) lpexists;

	constructor(address[] memory _lps) {
		lpsToSkim = _lps;
	}
	
	function allLps() public view returns (address[] memory) {
	    return lpsToSkim;
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
	
	function skim(address to) public {
		require(msg.sender == skimmer);
		uint256 i = 0;
		while (i < lpsToSkim.length) {
			skimInterface(lpsToSkim[i]).skim(to);
			i += 1;
		}
	}
}
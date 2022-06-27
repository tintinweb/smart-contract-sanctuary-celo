pragma solidity ^0.7.0;

interface skimInterface {
	function skim(address to) external;
}

contract PrincipalSkimmer {
	address[] public lpsToSkim;
	address skimmer = 0x786798aDDD58507B3F9466a1365242868Cd96A5B;

	constructor(address[] memory _lps) {
		lpsToSkim = _lps;
	}

	function changeSkimmer(address to) public {
		require(msg.sender == skimmer);
		skimmer = to;
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
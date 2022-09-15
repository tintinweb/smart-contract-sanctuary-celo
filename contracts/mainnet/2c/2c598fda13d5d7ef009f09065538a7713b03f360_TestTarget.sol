pragma solidity 0.8.11;

contract TestTarget{
    event GovernanceWorks();
    address public timelock = 0xF9d414813e189c1b6dB7Fce7806aF42629239e38;
    bool public governanceWorks = false;

    function signalGovernanceWorks() external {
        require(msg.sender == timelock, 'Invalid caller');
        governanceWorks = true;
        emit GovernanceWorks(); }
}
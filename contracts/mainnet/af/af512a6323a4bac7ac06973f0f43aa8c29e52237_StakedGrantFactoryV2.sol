// SPDX-License-Identifier: Apache-2.0
// https://docs.soliditylang.org/en/v0.8.10/style-guide.html
pragma solidity ^0.8.10;

contract StakedGrantFactoryV2 {
    constructor() {}

    event StakedGrantCreated(
        address indexed owner,
        address indexed beneficiary,
        address indexed stakedGrant,
        address qbGrantID,
        uint96 qbApplicationID
    );

    function createStakedGrant(
        address _beneficiary,
        address _qbGrantID,
        uint96 _qbApplicationID
    ) public {
        emit StakedGrantCreated(
            msg.sender,
            _beneficiary,
            address(this),
            _qbGrantID,
            _qbApplicationID
        );
    }
}
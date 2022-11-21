// SPDX-License-Identifier: Unknown
// Solidity program to implement
pragma solidity 0.8.12;

contract PaggloAmbec {
    address private owner;

    mapping(uint256 => Event[]) private eventsArray;

    /// Struct containing to register events
    struct Event {
        uint256 id;
        string idTransaction;
        string evento;
        string message;
    }

    constructor() {
        owner = msg.sender;
    }

    /*
     * returns all events
     */
    modifier ownerOnly() {
        assert(msg.sender == owner);
        _;
    }

    /**
     * @dev Store value in array
     * @param _id, _idTransactionton, _evento, _message
     */
    function addEvent(
        uint256 _id,
        string memory _idTransaction,
        string memory _evento,
        string memory _message
    ) public ownerOnly {
        eventsArray[_id].push(Event(_id, _idTransaction, _evento, _message));
    }

    /*
     * @return events value of '_id'
     */
    function getAllEvents(uint256 _id)
        external
        view
        virtual
        returns (Event[] memory)
    {
        return eventsArray[_id];
    }
}
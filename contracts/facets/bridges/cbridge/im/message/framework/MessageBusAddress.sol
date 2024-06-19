// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

abstract contract MessageBusAddress {
    /// Storage ///
    bytes32 internal constant MSG_BUS_ADDRESS_NAMESPACE = keccak256("exchange.rango.facets.cbridge.msg.messagebusaddress");

    struct MsgBusAddrStorage {
        address messageBus;
    }

    event MessageBusUpdated(address messageBus);

    function setMessageBusInternal(address _messageBus) internal {
        require(_messageBus != address(0), "Invalid Address messagebus");
        MsgBusAddrStorage storage s = getMsgBusAddrStorage();
        s.messageBus = _messageBus;
        emit MessageBusUpdated(s.messageBus);
    }

    function getMsgBusAddress() internal view returns (address) {
        MsgBusAddrStorage storage s = getMsgBusAddrStorage();
        return s.messageBus;
    }

    /// @dev fetch local storage
    function getMsgBusAddrStorage() private pure returns (MsgBusAddrStorage storage s) {
        bytes32 namespace = MSG_BUS_ADDRESS_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }

}

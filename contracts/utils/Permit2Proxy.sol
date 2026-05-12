// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { ISignatureTransfer } from "permit2/src/interfaces/ISignatureTransfer.sol";
import { PermitHash } from "permit2/src/libraries/PermitHash.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

contract Permit2Proxy is Ownable, EIP712 {
    using SafeERC20 for IERC20;

    error CallToDiamondFailed(bytes revertData);
    error InvalidRecipient();
    error InvalidTokenAddress();
    error InvalidCalldataSignature();

    IPermit2 public permit2;
    address public immutable rangoDiamond;

    string internal constant WITNESS_TYPE_STRING =
        "WitnessData witness)TokenPermissions(address token,uint256 amount)WitnessData(address diamondAddress,bytes32 diamondCalldata)";
    bytes32 internal constant WITNESS_STRUCT_TYPEHASH =
        keccak256("WitnessData(address diamondAddress,bytes32 diamondCalldata)");
    bytes32 internal constant FULL_WITNESS_TYPEHASH =
        keccak256(abi.encodePacked(PermitHash._PERMIT_TRANSFER_FROM_WITNESS_TYPEHASH_STUB, WITNESS_TYPE_STRING));

    bytes32 internal constant CALLDATA_WITNESS_TYPEHASH =
        keccak256("CalldataWitness(address owner,address token,uint256 amount,bytes32 diamondCalldataHash)");

    struct WitnessData {
        address diamondAddress;
        bytes32 diamondCalldata;
    }

    constructor(address _permit2Address, address _diamondAddress, address _owner) Ownable(_owner) EIP712("Permit2Proxy", "1") {
        permit2 = IPermit2(_permit2Address);
        rangoDiamond = _diamondAddress;
    }

    function permit2WitnessTransferAndCallDiamond(
        ISignatureTransfer.PermitTransferFrom calldata permit,
        bytes calldata signature,
        address signer,
        bytes calldata diamondCalldata
    ) external payable returns (bytes memory) {
        ISignatureTransfer.SignatureTransferDetails memory transferDetails =
            ISignatureTransfer.SignatureTransferDetails({
                to: address(this),
                requestedAmount: permit.permitted.amount
            });

        WitnessData memory witnessData = WitnessData({
            diamondAddress: rangoDiamond,
            diamondCalldata: keccak256(diamondCalldata)
        });

        bytes32 witness = _hashWitnessData(witnessData);

        permit2.permitWitnessTransferFrom(
            permit,
            transferDetails,
            signer,
            witness,
            WITNESS_TYPE_STRING,
            signature
        );

        _maxApproveDiamond(permit.permitted.token);

        return _callRangoDiamond(diamondCalldata);
    }

    function permitAndCallDiamond(
        address owner,
        address token,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        bytes calldata diamondCalldata,
        bytes calldata calldataSignature
    ) external payable returns (bytes memory) {
        if (token == address(0)) revert InvalidTokenAddress();

        // Verify the owner signed the calldata
        bytes32 structHash = keccak256(abi.encode(
            CALLDATA_WITNESS_TYPEHASH,
            owner,
            token,
            amount,
            keccak256(diamondCalldata)
        ));
        bytes32 digest = _hashTypedDataV4(structHash);
        address recovered = ECDSA.recover(digest, calldataSignature);
        if (recovered != owner) revert InvalidCalldataSignature();

        // Execute permit (skip if allowance already sufficient)
        IERC20 erc20 = IERC20(token);
        if (erc20.allowance(owner, address(this)) < amount) {
            IERC20Permit(token).permit(owner, address(this), amount, deadline, v, r, s);
        }

        erc20.safeTransferFrom(owner, address(this), amount);

        _maxApproveDiamond(token);

        return _callRangoDiamond(diamondCalldata);
    }

    function rescueFunds(address token, address recipient, uint256 amount) external onlyOwner {
        if (recipient == address(0)) revert InvalidRecipient();

        if (token == address(0)) {
            (bool success,) = recipient.call{value: amount}("");
            require(success, "Native transfer failed");
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }
    }

    function _maxApproveDiamond(address token) internal {
        if (token == address(0)) return;
        SafeERC20.forceApprove(IERC20(token), rangoDiamond, type(uint256).max);
    }

    function _hashWitnessData(WitnessData memory witnessData) internal pure returns (bytes32) {
        return keccak256(abi.encode(WITNESS_STRUCT_TYPEHASH, witnessData.diamondAddress, witnessData.diamondCalldata));
    }

    function _callRangoDiamond(bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory result) = rangoDiamond.call{value: msg.value}(data);
        if (!success) {
            revert CallToDiamondFailed(result);
        }
        return result;
    }

    function getWitnessTypehash() external pure returns (bytes32) {
        return FULL_WITNESS_TYPEHASH;
    }

    function getWitnessTypeString() external pure returns (string memory) {
        return WITNESS_TYPE_STRING;
    }
}

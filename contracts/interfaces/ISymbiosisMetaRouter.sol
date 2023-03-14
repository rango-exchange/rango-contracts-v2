// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./IRangoSymbiosis.sol";

interface ISymbiosisMetaRouter {
    function metaRoute(IRangoSymbiosis.MetaRouteTransaction calldata metaRouteTransaction) external payable;
}

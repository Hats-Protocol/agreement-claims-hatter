// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Test, console2 } from "forge-std/Test.sol";
import { AgreementClaimsHatter } from "../src/AgreementClaimsHatter.sol";
import { Deploy } from "../script/AgreementClaimsHatter.s.sol";

contract AgreementClaimsHatterTest is Deploy, Test {
  // variables inhereted from Deploy script
  // Counter public AgreementClaimsHatter;

  uint256 public fork;
  uint256 public BLOCK_NUMBER;
  string public version;

  function setUp() public virtual {
    // create and activate a fork, at BLOCK_NUMBER
    // fork = vm.createSelectFork(vm.rpcUrl("mainnet"), BLOCK_NUMBER);

    // deploy via the script
    Deploy.prepare(false, version); // set first param to true to log deployment addresses
    Deploy.run();
  }
}

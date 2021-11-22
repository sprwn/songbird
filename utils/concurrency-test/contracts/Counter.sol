// (c) 2021, Flare Networks Limited. All rights reserved.
// Please see the file LICENSE for licensing terms.

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Counter {
  uint256 public count;

  constructor() {
  }

  function increment() public {
    count += 1;
  }
}

pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./Pve.sol";

contract PveTest is DSTest {
    Pve pve;

    function setUp() public {
        pve = new Pve();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}

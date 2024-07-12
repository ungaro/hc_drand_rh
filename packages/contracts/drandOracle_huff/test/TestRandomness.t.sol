// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
// Force recompilation
import "forge-std/Test.sol";
import "forge-std/console.sol";

import "foundry-huff/HuffDeployer.sol";

interface IDrandOracle {
    function unsafeGetDrand(uint256) external view returns (uint256);
    function getDrand(uint256) external view returns (uint256);
    function isDrandAvailable(uint256) external view returns (bool);
    function setDrand(uint256,uint256) external;
}

interface ISequencerRandomOracle {
    function unsafeGetSequencerRandom(uint256) external view returns (uint256);
    function isSequencerRandomAvailable(uint256) external view returns (bool);
    function getSequencerRandom(uint256) external view returns (uint256);
    function postCommitment(uint256,bytes32) external;
    function reveal(uint256,uint256) external;
    function getLastRevealedT() external view returns (uint256);
    function getCommitment(uint256) external view returns (bytes32,bool,uint256);
}

interface IRandomnessOracle {
    function unsafeGetRandomness(uint256) external view returns (uint256);
    function getRandomness(uint256) external view returns (uint256);
    function isRandomnessAvailable(uint256) external view returns (bool);
}

contract TestRandomness is Test {
    IDrandOracle drandOracle;
    ISequencerRandomOracle sequencerRandomOracle;
    IRandomnessOracle randomnessOracle;
    event Debug(string message, uint256 value);
    address owner = address(this);

    uint256 constant DRAND_TIMEOUT = 10;
    uint256 constant SEQUENCER_TIMEOUT = 10;
    uint256 constant PRECOMMIT_DELAY = 10;
    uint256 constant DELAY = 10;

    function setUp() public {
        drandOracle = IDrandOracle(HuffDeployer.deploy("DrandOracle"));
        sequencerRandomOracle = ISequencerRandomOracle(HuffDeployer.deploy("SequencerRandomOracle"));
        
        // Deploy RandomnessOracle with constructor arguments
        bytes memory args = abi.encode(address(drandOracle), address(sequencerRandomOracle));
        randomnessOracle = IRandomnessOracle(HuffDeployer.deploy_with_args("RandomnessOracle", args));
    }

    function testDrandValue() public {
        uint256 timestamp = block.timestamp;
        uint256 drandValue = 12345;
        
        vm.warp(timestamp);
        drandOracle.setDrand(timestamp, drandValue);

        assertEq(drandOracle.getDrand(timestamp), drandValue);
        assertEq(drandOracle.unsafeGetDrand(timestamp), drandValue);
    }
    
    
event SetDrandValue(uint256 value);
event GetDrandValue(uint256 value);
event FunctionCalled(bytes4 selector);

function testSetDrand() public {
    vm.warp(101);

    uint256 timestamp = block.timestamp;
    uint256 drandValue = 12345;

    bytes4 setSelector = bytes4(keccak256("setDrand(uint256,uint256)"));
    bytes4 getSelector = bytes4(keccak256("getDrand(uint256)"));
    console.log("setDrand selector:", toHexString(uint32(setSelector)));
    console.log("getDrand selector:", toHexString(uint32(getSelector)));

    vm.recordLogs();
    drandOracle.setDrand(timestamp, drandValue);
    console.log("setDrand called");

    Vm.Log[] memory logs = vm.getRecordedLogs();
    for (uint i = 0; i < logs.length; i++) {
        console.log("Log", i);
        console.logBytes32(logs[i].topics[0]);
        if (logs[i].data.length > 0) {
            console.logBytes(logs[i].data);
        }
    }

    // Check storage directly
    bytes32 storageValue = vm.load(address(drandOracle), bytes32(uint256(timestamp)));
    console.log("Direct storage value:", uint256(storageValue));

    uint256 storedValue;
    try drandOracle.getDrand(timestamp) returns (uint256 returnedValue) {
        storedValue = returnedValue;
        console.log("getDrand returned:", storedValue);
    } catch Error(string memory reason) {
        console.log("getDrand call failed with reason:", reason);
    } catch (bytes memory lowLevelData) {
        console.log("getDrand call failed with low-level error");
        console.logBytes(lowLevelData);
    }

    assertEq(storedValue, drandValue, "Stored value does not match input value");
}
function toHexString(uint32 value) internal pure returns (string memory) {
    bytes memory buffer = new bytes(10);
    buffer[0] = '0';
    buffer[1] = 'x';
    for (uint256 i = 9; i > 1; --i) {
        buffer[i] = bytes1(uint8(48 + uint256(value & 0xf)));
        value >>= 4;
    }
    return string(buffer);
}

    function testDrandTimeout() public {
        uint256 timestamp = block.timestamp;
        uint256 drandValue = 12345;
        
        vm.warp(timestamp + DRAND_TIMEOUT + 1);
        vm.expectRevert("Drand backfill timeout expired");
        drandOracle.setDrand(timestamp, drandValue);
    }

    function testSequencerCommitmentAndReveal() public {
        uint256 currentTimestamp = block.timestamp;
        uint256 futureTimestamp1 = currentTimestamp + PRECOMMIT_DELAY + 1;
        uint256 futureTimestamp2 = futureTimestamp1 + 1;
        uint256 futureTimestamp3 = futureTimestamp2 + 1;
        uint256 randomValue = 67890;
        bytes32 commitment1 = keccak256(abi.encodePacked(randomValue));
        bytes32 commitment2 = keccak256(abi.encodePacked(randomValue + 1));
        bytes32 commitment3 = keccak256(abi.encodePacked(randomValue + 2));

        sequencerRandomOracle.postCommitment(futureTimestamp1, commitment1);
        sequencerRandomOracle.postCommitment(futureTimestamp2, commitment2);
        sequencerRandomOracle.postCommitment(futureTimestamp3, commitment3);

        vm.expectRevert("No commitment posted");
        sequencerRandomOracle.reveal(futureTimestamp1 - 1, randomValue);

        vm.warp(futureTimestamp1);
        sequencerRandomOracle.reveal(futureTimestamp1, randomValue);
        assertEq(sequencerRandomOracle.getSequencerRandom(futureTimestamp1), randomValue);

        vm.expectRevert("Already revealed");
        sequencerRandomOracle.reveal(futureTimestamp1, randomValue);

        vm.warp(futureTimestamp3);
        
        vm.expectRevert("Must reveal in order");
        sequencerRandomOracle.reveal(futureTimestamp2, randomValue + 2);
        sequencerRandomOracle.reveal(futureTimestamp3, randomValue + 2);
    }

    function testSequencerTimeout() public {
        uint256 currentTimestamp = block.timestamp;
        uint256 futureTimestamp = currentTimestamp + PRECOMMIT_DELAY + 1;
        uint256 randomValue = 67890;
        bytes32 commitment = keccak256(abi.encodePacked(randomValue));

        sequencerRandomOracle.postCommitment(futureTimestamp, commitment);

        vm.warp(futureTimestamp + SEQUENCER_TIMEOUT + 1);
        vm.expectRevert("Reveal timeout expired");
        sequencerRandomOracle.reveal(futureTimestamp, randomValue);
    }

    function testRandomnessOracle() public {
        uint256 currentTimestamp = block.timestamp;
        uint256 futureTimestamp = currentTimestamp + DELAY + PRECOMMIT_DELAY + 1;
        uint256 drandValue = 12345;
        uint256 sequencerValue = 67890;
        bytes32 commitment = keccak256(abi.encodePacked(sequencerValue));

        drandOracle.setDrand(futureTimestamp - DELAY, drandValue);
        sequencerRandomOracle.postCommitment(futureTimestamp, commitment);
        
        vm.warp(futureTimestamp);
        sequencerRandomOracle.reveal(futureTimestamp, sequencerValue);

        uint256 expectedRandomness = uint256(keccak256(abi.encodePacked(drandValue, sequencerValue)));
        assertEq(randomnessOracle.getRandomness(futureTimestamp), expectedRandomness);
    }

    function testRandomnessNotAvailable() public {
        vm.warp(20);
        uint256 timestamp = block.timestamp;

        vm.expectRevert("Randomness not available");
        randomnessOracle.getRandomness(timestamp);

        assertEq(randomnessOracle.unsafeGetRandomness(timestamp), 0);
    }

    function testIsRandomnessAvailable() public {
        uint256 currentTimestamp = block.timestamp;
        uint256 futureTimestamp = currentTimestamp + PRECOMMIT_DELAY + 1;
        uint256 drandValue = 12345;
        uint256 sequencerValue = 67890;
        bytes32 commitment = keccak256(abi.encodePacked(sequencerValue));

        assertFalse(randomnessOracle.isRandomnessAvailable(futureTimestamp));

        drandOracle.setDrand(futureTimestamp - DELAY, drandValue);
        assertFalse(randomnessOracle.isRandomnessAvailable(futureTimestamp));

        sequencerRandomOracle.postCommitment(futureTimestamp, commitment);
        assertTrue(randomnessOracle.isRandomnessAvailable(futureTimestamp));

        vm.warp(futureTimestamp);
        sequencerRandomOracle.reveal(futureTimestamp, sequencerValue);
        assertTrue(randomnessOracle.isRandomnessAvailable(futureTimestamp));
    }
}
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
    function setDrand(uint256, uint256) external;
}


interface ISequencerRandomOracle {
    function unsafeGetSequencerRandom(uint256) external view returns (uint256);
    function isSequencerRandomAvailable(uint256) external view returns (bool);
    function getSequencerRandom(uint256) external view returns (uint256);
    function postCommitment(uint256, bytes32) external;
    function reveal(uint256, uint256) external; // Note: No return value
    function getLastRevealedT() external view returns (uint256);
    function getCommitment(uint256) external view returns (bytes32, bool, uint256);
    function changeOwner(address) external;
    function owner() external view returns (address);

    event ValueRevealed(uint256 indexed T, uint256 value);
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
    //address OWNER = makeAddr("Owner");

    event SetDrandValue(uint256 value);
    event GetDrandValue(uint256 value);
    event FunctionCalled(bytes4 selector);
    event Debug(string message, uint256 value);
    event ValueRevealed(uint256 indexed T, uint256 value);

    address owner = address(this);
    
    address prankowner = address(0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f);
    uint256 constant DRAND_TIMEOUT = 10;
    uint256 constant SEQUENCER_TIMEOUT = 10;
    uint256 constant PRECOMMIT_DELAY = 10;
    uint256 constant DELAY = 10;

function setUp() public {
    console.log("OWNER");
    console.logBytes(abi.encode(prankowner));

    // Deploy DrandOracle
    address drandOracleAddress = HuffDeployer
        .config()
        .with_args(abi.encode(prankowner))
        .deploy("DrandOracle");
    drandOracle = IDrandOracle(drandOracleAddress);



    bytes memory sequencerRandomOracleArgs = abi.encode(prankowner);
    address sequencerRandomOracleAddress = HuffDeployer
        .config()
        .with_args(abi.encode(prankowner))
        .deploy("SequencerRandomOracle");
    sequencerRandomOracle = ISequencerRandomOracle(sequencerRandomOracleAddress);




    // Deploy RandomnessOracle
    bytes memory randomnessOracleArgs = abi.encode(drandOracleAddress, sequencerRandomOracleAddress);
    address randomnessOracleAddress = HuffDeployer
        .config()
        .with_args(randomnessOracleArgs)
        .deploy("RandomnessOracle");
    randomnessOracle = IRandomnessOracle(randomnessOracleAddress);

    // Print deployed addresses for verification
    console.log("DrandOracle deployed at:", drandOracleAddress);
    console.log("SequencerRandomOracle deployed at:", sequencerRandomOracleAddress);
    console.log("RandomnessOracle deployed at:", randomnessOracleAddress);
}



function testDrandValue() public {
    vm.recordLogs();

    uint256 timestamp = block.timestamp;
    uint256 drandValue = 12345;

    // Test setting at exactly T
    vm.warp(timestamp);
    vm.prank(prankowner);
    vm.store(address(drandOracle), keccak256(abi.encode(timestamp)), bytes32(0));

    try drandOracle.setDrand(timestamp, drandValue) {
        console.log("setDrand succeeded at T");
    } catch Error(string memory reason) {
        console.log("setDrand failed with reason at T:", reason);
    } catch (bytes memory lowLevelData) {
        console.log("setDrand failed with low-level error at T");
        console.logBytes(lowLevelData);
    }

    try drandOracle.getDrand(timestamp) returns (uint256 storedValue) {
        console.log("getDrand succeeded at T");
        assertEq(storedValue, drandValue, "Stored value doesn't match at T");
    } catch Error(string memory reason) {
        console.log("getDrand failed with reason at T:", reason);
    } catch (bytes memory lowLevelData) {
        console.log("getDrand failed with low-level error at T");
        console.logBytes(lowLevelData);
    }

    // Test setting at T + DRAND_TIMEOUT
    uint256 newTimestamp = timestamp + DRAND_TIMEOUT;
    vm.warp(newTimestamp);
    vm.prank(prankowner);

    try drandOracle.setDrand(newTimestamp, drandValue + 1) {
        console.log("setDrand succeeded at T + DRAND_TIMEOUT");
    } catch Error(string memory reason) {
        console.log("setDrand failed with reason at T + DRAND_TIMEOUT:", reason);
    } catch (bytes memory lowLevelData) {
        console.log("setDrand failed with low-level error at T + DRAND_TIMEOUT");
        console.logBytes(lowLevelData);
    }

    try drandOracle.getDrand(newTimestamp) returns (uint256 storedValue) {
        console.log("getDrand succeeded at T + DRAND_TIMEOUT");
        assertEq(storedValue, drandValue + 1, "Stored value doesn't match at T + DRAND_TIMEOUT");
    } catch Error(string memory reason) {
        console.log("getDrand failed with reason at T + DRAND_TIMEOUT:", reason);
    } catch (bytes memory lowLevelData) {
        console.log("getDrand failed with low-level error at T + DRAND_TIMEOUT");
        console.logBytes(lowLevelData);
    }

    // Test setting after T + DRAND_TIMEOUT (should fail)
    uint256 finalTimestamp = newTimestamp + 1;
    vm.warp(finalTimestamp);
    vm.prank(prankowner);
    vm.expectRevert("Drand backfill timeout expired");

    try drandOracle.setDrand(finalTimestamp, drandValue + 2) {
        console.log("setDrand unexpectedly succeeded after T + DRAND_TIMEOUT");
    } catch Error(string memory reason) {
        console.log("setDrand correctly failed with reason after T + DRAND_TIMEOUT:", reason);
    } catch (bytes memory lowLevelData) {
        console.log("setDrand failed with low-level error after T + DRAND_TIMEOUT");
        console.logBytes(lowLevelData);
    }

    // Log all recorded events
    Vm.Log[] memory logs = vm.getRecordedLogs();
    for (uint i = 0; i < logs.length; i++) {
        console.log("Log", i);
        console.logBytes32(logs[i].topics[0]);
        if (logs[i].data.length > 0) {
            console.logBytes(logs[i].data);
        }
    }
}

    function testOwner() public {
        bytes32 ownerFromStorage = vm.load(
            address(drandOracle),
            bytes32(uint256(0))
        );
        assertEq(
            address(uint160(uint256(ownerFromStorage))),
            prankowner,
            "Owner not set correctly"
        );
    }

    function testSetDrand() public {
        vm.recordLogs();

        vm.prank(prankowner);
        vm.warp(101);
        uint256 timestamp = block.timestamp;
        uint256 drandValue = 12345;

        bytes4 setSelector = bytes4(keccak256("setDrand(uint256,uint256)"));
        bytes4 getSelector = bytes4(keccak256("getDrand(uint256)"));
        console.log("setDrand selector:", toHexString(uint32(setSelector)));
        console.log("getDrand selector:", toHexString(uint32(getSelector)));

        try drandOracle.setDrand(timestamp, drandValue) {
            console.log("setDrand succeeded");
        } catch Error(string memory reason) {
            console.log("setDrand failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("setDrand failed with low-level error");
            console.logBytes(lowLevelData);
        }

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint i = 0; i < logs.length; i++) {
            console.log("Log", i);
            console.logBytes32(logs[i].topics[0]);
            if (logs[i].data.length > 0) {
                console.logBytes(logs[i].data);
            }
        }

        // Print the owner address from storage
        bytes32 ownerFromStorage = vm.load(
            address(drandOracle),
            bytes32(uint256(0))
        );
        console.log(
            "Owner from storage:",
            address(uint160(uint256(ownerFromStorage)))
        );
        console.log("Expected owner:", owner);
    }

    function toHexString(uint32 value) internal pure returns (string memory) {
        bytes memory buffer = new bytes(10);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 9; i > 1; --i) {
            buffer[i] = bytes1(uint8(48 + uint256(value & 0xf)));
            value >>= 4;
        }
        return string(buffer);
    }
    
    function testSequencerTimeout() public {
    uint256 currentTimestamp = block.timestamp;
    uint256 futureTimestamp = currentTimestamp + PRECOMMIT_DELAY + 1;
    uint256 randomValue = 67890;
    bytes32 commitment = keccak256(abi.encodePacked(randomValue));
    
    address storedOwner = sequencerRandomOracle.owner();
    console.log("Stored owner in SequencerRandomOracle:", storedOwner);
    console.log("Current timestamp:", currentTimestamp);
    console.log("Future timestamp:", futureTimestamp);
    console.log("SEQUENCER_TIMEOUT:", SEQUENCER_TIMEOUT);

    vm.prank(storedOwner);
    sequencerRandomOracle.postCommitment(futureTimestamp, commitment);

    // Test reveal before timeout (should succeed)
    uint256 revealTimestamp = futureTimestamp + SEQUENCER_TIMEOUT - 1;
    vm.warp(revealTimestamp);
    
    console.log("Current block timestamp before reveal:", block.timestamp);
    console.log("Revealing for timestamp:", futureTimestamp);
    console.log("With random value:", randomValue);
    
    vm.expectEmit(true, true, false, true);
    emit ValueRevealed(futureTimestamp, randomValue);
    
    vm.recordLogs();
    
    (bool success, bytes memory returnData) = address(sequencerRandomOracle).call(
        abi.encodeWithSignature("reveal(uint256,uint256)", futureTimestamp, randomValue)
    );

    console.log("Reveal call success:", success);
    if (success) {
        console.log("Reveal before timeout succeeded");
        uint256 returnValue = abi.decode(returnData, (uint256));
        console.log("Return value:", returnValue);
        require(returnValue == 1, "Expected return value of 1");
    } else {
        console.log("Reveal before timeout failed");
        if (returnData.length > 0) {
            console.log("Revert reason:", abi.decode(returnData, (string)));
        } else {
            console.log("No revert reason provided");
        }
    }
   Vm.Log[] memory logs = vm.getRecordedLogs();
    for (uint i = 0; i < logs.length; i++) {
        bytes32 topic = logs[i].topics[0];
        if (topic == keccak256("EnterREVEAL()")) {
            console.log("Entered REVEAL function");
        } else if (topic == keccak256("CalldataSize(uint256)")) {
            uint256 size = abi.decode(logs[i].data, (uint256));
            console.log("Calldata size:", size);
        } else if (topic == keccak256("BeforeLoadingT()")) {
            console.log("Before loading T");
        } else if (topic == keccak256("AfterLoadingT(uint256)")) {
            uint256 T = abi.decode(logs[i].data, (uint256));
            console.log("After loading T:", T);
        } else if (topic == keccak256("AfterDupT(uint256)")) {
            uint256 T = abi.decode(logs[i].data, (uint256));
            console.log("After dup T:", T);
        } else if (topic == keccak256("BeforeLoadingValue()")) {
            console.log("Before loading value");
        } else if (topic == keccak256("AfterLoadingValue(uint256)")) {
            uint256 value = abi.decode(logs[i].data, (uint256));
            console.log("After loading value:", value);
        } else if (topic == keccak256("AfterDupValue(uint256)")) {
            uint256 value = abi.decode(logs[i].data, (uint256));
            console.log("After dup value:", value);
        } else if (topic == keccak256("BeforeTimeoutCheck()")) {
            console.log("Before timeout check");
        } else if (topic == keccak256("AfterLoadingTimestamp(uint256)")) {
            uint256 timestamp = abi.decode(logs[i].data, (uint256));
            console.log("After loading timestamp:", timestamp);
        } else if (topic == keccak256("AfterCalculatingThreshold(uint256)")) {
            uint256 threshold = abi.decode(logs[i].data, (uint256));
            console.log("After calculating threshold:", threshold);
        } else if (topic == keccak256("AfterComparisonResult(uint256)")) {
            uint256 result = abi.decode(logs[i].data, (uint256));
            console.log("After comparison result:", result);
        } else if (topic == keccak256("AfterTimeoutJump()")) {
            console.log("After timeout jump");
        } else if (topic == keccak256("RevealSuccessful()")) {
            console.log("Reveal was successful");
        } else if (topic == keccak256("RevealTimeout()")) {
            console.log("Reveal timed out");
        } else {
            console.log("Unknown log:");
            console.logBytes32(topic);
            console.logBytes(logs[i].data);
        }
    }


    require(success && logs.length > 0 && logs[logs.length - 1].topics[0] == keccak256("RevealSuccessful()"), "Reveal before timeout should succeed");

    // Test reveal after timeout (should revert)
    vm.warp(futureTimestamp + SEQUENCER_TIMEOUT + 1);
    vm.expectRevert(abi.encodeWithSignature("RevealTimeoutExpired()"));
    sequencerRandomOracle.reveal(futureTimestamp, randomValue);
}
    function testRandomnessOracle() public {
        uint256 currentTimestamp = block.timestamp;
        uint256 futureTimestamp = currentTimestamp +
            DELAY +
            PRECOMMIT_DELAY +
            1;
        uint256 drandValue = 12345;
        uint256 sequencerValue = 67890;
        bytes32 commitment = keccak256(abi.encodePacked(sequencerValue));
        vm.prank(owner);

        drandOracle.setDrand(futureTimestamp - DELAY, drandValue);
        sequencerRandomOracle.postCommitment(futureTimestamp, commitment);

        vm.warp(futureTimestamp);
        sequencerRandomOracle.reveal(futureTimestamp, sequencerValue);

        uint256 expectedRandomness = uint256(
            keccak256(abi.encodePacked(drandValue, sequencerValue))
        );
        assertEq(
            randomnessOracle.getRandomness(futureTimestamp),
            expectedRandomness
        );
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
        vm.prank(prankowner);

        drandOracle.setDrand(futureTimestamp - DELAY, drandValue);
        assertFalse(randomnessOracle.isRandomnessAvailable(futureTimestamp));

        sequencerRandomOracle.postCommitment(futureTimestamp, commitment);
        assertTrue(randomnessOracle.isRandomnessAvailable(futureTimestamp));

        vm.warp(futureTimestamp);
        sequencerRandomOracle.reveal(futureTimestamp, sequencerValue);
        assertTrue(randomnessOracle.isRandomnessAvailable(futureTimestamp));
    }
}

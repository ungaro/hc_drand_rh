// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
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
    error RevealTimeoutNotExpired();
    error NoCommitmentFound();
    error InvalidRevealedValue();
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

    error RevealTimeoutNotExpired();
    error NoCommitmentFound();
    error InvalidRevealedValue();


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


function fundAccountIfNeeded(address account, uint256 minimumBalance) internal {
    uint256 currentBalance = address(account).balance;
    if (currentBalance < minimumBalance) {
        uint256 amountToFund = minimumBalance - currentBalance;
        vm.deal(account, currentBalance + amountToFund);
        console.log("Funded account with:", amountToFund);
    }
}

function testSequencerTimeout() public {
    uint256 currentTimestamp = block.timestamp;
    uint256 futureTimestamp = currentTimestamp + PRECOMMIT_DELAY + 1;
    uint256 randomValue = 67890;
    bytes32 commitment = keccak256(abi.encodePacked(randomValue));
    
    address storedOwner = sequencerRandomOracle.owner();
    
    // Ensure the account has enough balance
    uint256 minimumBalance = 1 ether;
    fundAccountIfNeeded(storedOwner, minimumBalance);

    console.log("Initial balance:", address(storedOwner).balance);

    vm.prank(storedOwner);
    sequencerRandomOracle.postCommitment(futureTimestamp, commitment);

    console.log("Balance after postCommitment:", address(storedOwner).balance);

    vm.warp(futureTimestamp + SEQUENCER_TIMEOUT - 1);
    
     console.log("Before reveal() call");
    vm.recordLogs();
    (bool success, bytes memory returnData) = address(sequencerRandomOracle).call(
        abi.encodeWithSignature("reveal(uint256,uint256)", futureTimestamp, randomValue)
    );
    console.log("After reveal() call");

    console.log("Reveal call success:", success);
    if (!success) {
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
        if (topic == keccak256("ValueRevealed(uint256,uint256)")) {
            uint256 T = uint256(logs[i].topics[1]);
            uint256 value = uint256(logs[i].topics[2]);
            console.log("ValueRevealed event - T:", T);
            console.log("ValueRevealed event - value:", value);
        } else if (topic == keccak256("RevealValues(uint256,uint256)")) {
            (uint256 T, uint256 value) = abi.decode(logs[i].data, (uint256, uint256));
            console.log("RevealValues log - T:", T);
            console.log("RevealValues log - value:", value);
        } else {
            console.log("Unknown log:");
            console.logBytes32(topic);
            console.logBytes(logs[i].data);
        }
    }

    require(success, "Reveal before timeout should succeed");
}

function toHexString(uint256 value) internal pure returns (string memory) {
    if (value == 0) {
        return "0x0";
    }
    uint256 temp = value;
    uint256 length = 0;
    while (temp != 0) {
        length++;
        temp >>= 8;
    }
    return toHexString(value, length);
}

function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
    bytes memory buffer = new bytes(2 * length + 2);
    buffer[0] = "0";
    buffer[1] = "x";
    for (uint256 i = 2 * length + 1; i > 1; --i) {
        buffer[i] = bytes1(uint8(48 + uint256(value & 0xf)));
        value >>= 4;
    }
    return string(buffer);
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

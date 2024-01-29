// Mock LeverageStrategy for testing purposes
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC4626, Math} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IAuraBooster} from "../../contracts/interfaces/IAuraBooster.sol";
import {IBalancerVault} from "../../contracts/interfaces/IBalancerVault.sol";
import {IcrvUSD} from "../../contracts/interfaces/IcrvUSD.sol";
import {IcrvUSDController} from "../../contracts/interfaces/IcrvUSDController.sol";
import {IcrvUSDUSDCPool} from "../../contracts/interfaces/IcrvUSDUSDCPool.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBasicRewards} from "../../contracts/interfaces/IBasicRewards.sol";
import {BalancerUtils} from "../../contracts/periphery/BalancerUtils.sol";
import {AuraUtils} from "../../contracts/periphery/AuraUtils.sol";
import {CurveUtils} from "../../contracts/periphery/CurveUtils.sol";
import {LeverageStrategyStorage} from "../../contracts/LeverageStrategyStorage.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LeverageStrategy is
    ReentrancyGuard,
    AccessControl,
    LeverageStrategyStorage
{
    using Math for uint256;

    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    uint256 public constant FIXED_UNWIND_PERCENTAGE = 30 * 10 ** 10;
    uint256 public constant HUNDRED_PERCENT = 10 ** 12;

    int256 internal _strategyHealth;
    constructor(bytes32 _poolId){}

    //================================================EXTERNAL FUNCTIONS===============================================//

    // Mock call to strategyHealth
    function strategyHealth() external view returns (int256) {
        return _strategyHealth;
    }

    // Setter only available in Mock!
    function setStrategyHealth(int256 amount) external {
        _strategyHealth = amount;
    }

    // Implemented for later tests
    function _tokenToStake() internal view returns (IERC20) {
        return IERC20(address(1));
    }

    function unwindFromKeeper() external {

    }

    function investFromKeeper(uint256 amountInMin) external {

    }
}

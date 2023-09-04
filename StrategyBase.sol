// SPDX-License-Identifier: GPL-3.0-or-later
/*

________                                          ______________________ 
__  ___/___  ____________________________ ___________  __ \__    |_  __ \
_____ \_  / / /__  __ \_  ___/  _ \_  __ `__ \  _ \_  / / /_  /| |  / / /
____/ // /_/ /__  /_/ /  /   /  __/  / / / / /  __/  /_/ /_  ___ / /_/ / 
/____/ \__,_/ _  .___//_/    \___//_/ /_/ /_/\___//_____/ /_/  |_\____/  
              /_/                                                        
*/

pragma solidity >=0.7.0 <0.9.0;

// import { IStrategy } from "supreme/interfaces/IStrategy.sol";
// import { TokenType } from "supreme/structs/TokenType.sol";
// import { ERC721, ERC721TokenReceiver } from "solmate/tokens/ERC721.sol";
// import { ERC1155TokenReceiver } from "solmate/tokens/ERC1155.sol";
// import { ERC20 } from "solmate/tokens/ERC20.sol";
// import { ERC1155 } from "solmate/tokens/ERC1155.sol";
// import { InvalidAddress, Unauthorized } from "supreme/utils/Errors.sol";
// import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
// import { PositionReceipt } from "supreme/structs/Strategy.sol";

/// @title StrategyBase
/// @author Daoism Systems
/// @notice StrategyBase contract that is supposed to be extended by various strategies
/// @custom:security-contact contact@daoism.systems
abstract contract StrategyBase is IStrategy, ERC721TokenReceiver, ERC1155TokenReceiver {
    using SafeTransferLib for ERC20;

    address public immutable strategyModule;
    address public immutable vault;

    constructor(address strategyModuleAddress, address vaultAddress) {
        if (strategyModuleAddress == address(0) || vaultAddress == address(0)) {
            revert InvalidAddress();
        }
        strategyModule = strategyModuleAddress;
        vault = vaultAddress;
    }

    modifier onlyStrategyModule() {
        if (msg.sender != strategyModule) {
            revert Unauthorized();
        }
        _;
    }

    /// @inheritdoc IStrategy
    function invest(address msgSender, uint256[] calldata amounts, bytes calldata extraStrategyData)
        external
        payable
        onlyStrategyModule
        returns (PositionReceipt memory receipt)
    {
        return _invest(msgSender, amounts, extraStrategyData);
    }

    /// @inheritdoc IStrategy
    function claimRewards(address msgSender, bytes calldata extraStrategyData) external payable onlyStrategyModule {
        _claimRewards(msgSender, extraStrategyData);
    }

    /// @inheritdoc IStrategy
    function withdrawInvestment(address msgSender, uint256[] calldata amounts, bytes calldata extraStrategyData)
        external
        payable
        onlyStrategyModule
    {
        _withdrawInvestment(msgSender, amounts, extraStrategyData);
    }

    /// @inheritdoc IStrategy
    function rescueTokens(address token, uint256 tokenId, TokenType typ) external {
        if (typ == TokenType.ERC20) {
            return ERC20(token).safeTransfer(vault, ERC20(token).balanceOf(address(this)));
        }

        if (typ == TokenType.ERC721) {
            return ERC721(token).safeTransferFrom(address(this), vault, tokenId);
        }

        if (typ == TokenType.ERC1155) {
            return ERC1155(token).safeTransferFrom(
                address(this), vault, tokenId, ERC1155(token).balanceOf(address(this), tokenId), ""
            );
        }
    }

    /// @notice Invests token `amounts`
    /// @param amounts The amounts of tokens to invest
    /// @param msgSender The sender of the transaction
    /// @param extraStrategyData The extra startegy data that is passed to the Startegy
    /// @dev MUST transfer received LP tokens/NFT to the vault
    ///      MUST return the correct receipt
    /// @return receipt The position receipt
    function _invest(address msgSender, uint256[] calldata amounts, bytes calldata extraStrategyData)
        internal
        virtual
        returns (PositionReceipt memory receipt);

    /// @notice Withdraws token `amounts` and transfers it to the Vault
    /// @param msgSender The sender of the transaction
    /// @param amounts The amounts of tokens to withdraw
    /// @param extraStrategyData The extra startegy data that is passed to the Startegy
    function _withdrawInvestment(address msgSender, uint256[] calldata amounts, bytes calldata extraStrategyData)
        internal
        virtual;

    /// @notice Claims the rewards and transfers it to the Vault
    /// @param msgSender The sender of the transaction
    /// @param extraStrategyData The extra startegy data that is passed to the Startegy
    function _claimRewards(address msgSender, bytes calldata extraStrategyData) internal virtual;
}
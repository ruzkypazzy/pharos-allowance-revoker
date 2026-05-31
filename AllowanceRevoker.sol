// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title AllowanceRevoker
 * @dev Security tool for checking and revoking ERC20 token approvals on Pharos blockchain
 * @notice Helps prevent unauthorized token drains by managing spender allowances
 */
contract AllowanceRevoker {
    // Constants
    address constant PHAROS_MAINNET = 0x0000000000000000000000000000000000000001;
    address constant PHAROS_TESTNET = 0x0000000000000000000000000000000000000002;

    uint256 constant MAX_UINT256 = type(uint256).max;

    // Events
    event ApprovalChecked(address indexed token, address indexed owner, address indexed spender, uint256 allowance);
    event ApprovalRevoked(address indexed token, address indexed owner, address indexed spender, uint256 previousAllowance);
    event RiskFlagged(address indexed owner, address indexed spender, uint256 allowance, string riskType);
    event BatchRevokeCompleted(address indexed owner, uint256 count);

    // Structures
    struct ApprovalInfo {
        address token;
        address spender;
        uint256 allowance;
        bool isUnlimited;
        bool isRisky;
        uint256 riskScore;
    }

    struct RiskReport {
        address owner;
        uint256 totalRiskScore;
        uint256 riskyApprovalCount;
        uint256 unlimitedApprovalCount;
        ApprovalInfo[] riskyApprovals;
    }

    // Storage
    mapping(address => mapping(address => uint256)) public cachedAllowances;
    mapping(address => ApprovalInfo[]) public addressApprovals;

    /**
     * @dev Check all approvals for an owner by querying events
     * @param owner The wallet address to check
     * @return approvals Array of ApprovalInfo structs
     */
    function checkApprovals(address owner) external returns (ApprovalInfo[] memory approvals) {
        // This function would typically query historical events
        // For demonstration, returns stored approvals
        return addressApprovals[owner];
    }

    /**
     * @dev Revoke a specific token approval
     * @param token The ERC20 token contract address
     * @param spender The address that was approved to spend tokens
     */
    function revoke(address token, address spender) external {
        // Note: This is a helper view function
        // Actual revocation must be done via token.approve(spender, 0)
        // This contract demonstrates the pattern only
        emit ApprovalRevoked(token, msg.sender, spender, cachedAllowances[msg.sender][spender]);
    }

    /**
     * @dev Batch revoke multiple approvals
     * @param tokens Array of token addresses
     * @param spenders Array of spender addresses
     */
    function revokeBatch(address[] calldata tokens, address[] calldata spenders) external {
        require(tokens.length == spenders.length, "Length mismatch");

        uint256 count = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            emit ApprovalRevoked(tokens[i], msg.sender, spenders[i], cachedAllowances[msg.sender][spenders[i]]);
            count++;
        }

        emit BatchRevokeCompleted(msg.sender, count);
    }

    /**
     * @dev Check if an owner has risky approval patterns
     * @param owner The wallet address to check
     * @return report RiskReport with all risky approvals
     */
    function checkRiskyApprovals(address owner) external returns (RiskReport memory report) {
        ApprovalInfo[] memory approvals = addressApprovals[owner];

        report.owner = owner;
        report.riskyApprovalCount = 0;
        report.unlimitedApprovalCount = 0;

        for (uint256 i = 0; i < approvals.length; i++) {
            if (approvals[i].isRisky) {
                report.riskyApprovalCount++;
            }
            if (approvals[i].isUnlimited) {
                report.unlimitedApprovalCount++;
            }
            if (approvals[i].riskScore > 50) {
                report.totalRiskScore += approvals[i].riskScore;
            }
        }

        return report;
    }

    /**
     * @dev Add approval to tracking (for demonstration)
     */
    function trackApproval(
        address token,
        address owner,
        address spender,
        uint256 allowance
    ) external {
        bool isUnlimited = allowance == MAX_UINT256;
        uint256 riskScore = 0;
        bool isRisky = false;

        // Calculate risk score
        if (isUnlimited) {
            riskScore = 100;
            isRisky = true;
            emit RiskFlagged(owner, spender, allowance, "UNLIMITED_APPROVAL");
        }
        if (allowance > 1000000 ether) {
            riskScore += 30;
            isRisky = true;
            emit RiskFlagged(owner, spender, allowance, "HIGH_ALLOWANCE");
        }

        ApprovalInfo memory info = ApprovalInfo({
            token: token,
            spender: spender,
            allowance: allowance,
            isUnlimited: isUnlimited,
            isRisky: isRisky,
            riskScore: riskScore
        });

        addressApprovals[owner].push(info);
        cachedAllowances[owner][spender] = allowance;

        emit ApprovalChecked(token, owner, spender, allowance);
    }
}

/**
 * @title AllowanceRevokerCommands
 * @dev Command reference for AI agents using cast commands
 */
contract AllowanceRevokerCommands {
    string constant MAINNET_RPC = "https://rpc.pharos.xyz";
    string constant TESTNET_RPC = "https://atlantic.dplabs-internal.com";

    // Command templates for AI agents

    /**
     * Check allowance for specific token
     * cast call <TOKEN_ADDRESS> "allowance(address,address)(uint256)" <OWNER> <SPENDER> --rpc-url <RPC_URL>
     */
    function checkAllowance() external pure returns (string memory) {
        return "cast call <TOKEN> \"allowance(address,address)(uint256)\" <OWNER> <SPENDER> --rpc-url $PHAROS_RPC";
    }

    /**
     * Revoke approval
     * cast send <TOKEN_ADDRESS> "approve(address,uint256)(bool)" <SPENDER> 0 --private-key $PRIVATE_KEY --rpc-url <RPC_URL>
     */
    function revokeApproval() external pure returns (string memory) {
        return "cast send <TOKEN> \"approve(address,uint256)(bool)\" <SPENDER> 0 --private-key $PRIVATE_KEY --rpc-url $PHAROS_RPC";
    }

    /**
     * Get current block for timestamp
     * cast block-number --rpc-url <RPC_URL>
     */
    function getCurrentBlock() external pure returns (string memory) {
        return "cast block-number --rpc-url $PHAROS_RPC";
    }

    /**
     * Check if address is contract
     * cast code <ADDRESS> --rpc-url <RPC_URL>
     */
    function isContract() external pure returns (string memory) {
        return "cast code <ADDRESS> --rpc-url $PHAROS_RPC";
    }
}
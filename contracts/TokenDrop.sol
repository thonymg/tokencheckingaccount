pragma solidity ^0.4.10;

import "./IERC20Token.sol";
import "./SafeMath.sol";

/**
 * The problem: Handing out tokens is problematic, because the receiving account
 * also needs enough ether to send a transaction transferring the tokens to the
 * user's account.
 * 
 * The solution: Send the tokens using a 'token drop'. The recipient of the
 * tokens can claim them from the account by signing a message authorising
 * transfer of the tokens to a different account.
 *
 * Issuing:
 *  1. Generate a series of accounts (eg, using a mnemonic generator)
 *  2. Add an ERC20 authorisation for the TokenDrop contract
 *     sufficient to cover the number of tokens being distributed.
 *  3. Call TokenDrop.deposit() with the list of account addresses,
 *     the ERC20 token address, and the number of tokens to allocate to each address.
 * 
 * Redeeming:
 *  1. Have the user sign a message consisting of
 *     (token_drop_address, token_address, recipient).
 *  2. From any account, call `TokenDrop.redeemFor` or
 *     `TokenDrop.redeem` with the ERC20 token address, the recipient
 *     (optional), and the signature from step 1.
 */
contract TokenDrop is SafeMath {
    event TokensDeposited(address indexed token, address indexed owner, uint quantity);
    event TokensRedeemed(address indexed token, address indexed owner, address indexed recipient, uint quantity);
    
    // (erc20 address => (owner => balance))
    mapping(address=>mapping (address=>uint)) public balances;
    
    /**
     * @dev Credits tokens to a list of accounts. The caller must first
     *      provide this contract with an allowance equal to the required
     *      number of tokens.
     * @param token The address of the token contract.
     * @param addresses The list of addresses to credit tokens to.
     * @param quantity The number of tokens to issue to each address.
     */
    function deposit(IERC20Token token, address[] addresses, uint quantity) {
        // Transfer the required number of tokens to us
        assert(token.transferFrom(msg.sender, this, quantity * addresses.length));

        for(var i = 0; i < addresses.length; i++) {
            var addr = addresses[i];
            balances[token][addr] = safeAdd(balances[token][addr], quantity);
            TokensDeposited(token, addr, quantity);
        }        
    }
    
    /**
     * @dev Redeems tokens associated with an account, transferring the tokens to
     *      a new address.
     * @param recipient The address to send the tokens to.
     * @param token The address of the token being redeemed.
     * @param v (r, s) The ECDSA signature from a valid account address authorising
     *          the transfer.
     */
    function redeemFor(IERC20Token token, address recipient, uint8 v, bytes32 r, bytes32 s) {
        var addr = ecrecover(sha3(address(this), token, recipient), v, r, s);
        var quantity = balances[token][addr];
        assert(quantity > 0);
        delete balances[token][addr];
        
        TokensRedeemed(token, addr, recipient, quantity);
        assert(token.transfer(recipient, quantity));
    }
    
    /**
     * @dev Redeems tokens associated with an account, sending the tokens to the caller.
     * @param token The address of the token being redeemed.
     * @param v (r, s) The ECDSA signature from a valid account address authorising
     *          the transfer.
     */
    function redeem(IERC20Token token, uint8 v, bytes32 r, bytes32 s) {
        redeemFor(token, msg.sender, v, r, s);
    }
    
    /**
     * @dev Withdraws tokens owned by the sending account directly, without need
     *      for a signature.
     * @param token The address of the token being withdrawn.
    */
    function withdraw(IERC20Token token) {
        var quantity = balances[token][msg.sender];
        assert(quantity > 0);
        delete balances[token][msg.sender];
        
        TokensRedeemed(token, msg.sender, msg.sender, quantity);
        assert(token.transfer(msg.sender, quantity));
    }
}

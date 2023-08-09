// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import { console2 } from "forge-std/Test.sol"; // remove before deploy
import { HatsEligibilityModule, HatsModule, IHatsEligibility } from "hats-module/HatsEligibilityModule.sol";

/*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
//////////////////////////////////////////////////////////////*/

/// @dev Thrown when the caller does not wear the `OWNER_HAT`
error AgreementClaimsHatter_NotOwner();
/// @dev Thrown when the caller does not wear the `ARBITRATOR_HAT`
error AgreementClaimsHatter_NotArbitrator();
/// @dev Thrown when the new grace period is shorter than `MIN_GRACE`
error AgreementClaimsHatter_GraceTooShort();
/// @dev Thrown when the new grace period would end prior to `graceEndsAt`
error AgreementClaimsHatter_GraceNotOver();
/// @dev Thrown when attempting to sign (w/o claiming) the current `agreement` without having already claimed the hat
error AgreementClaimsHatter_HatNotClaimed();
/// @dev Thrown when the caller has already signed the current `agreement`
error AgreementClaimsHatter_AlreadySigned();

contract AgreementClaimsHatter is HatsEligibilityModule {
  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /// @dev Emitted when a user "signs" the `agreement` and claims the hat
  event AgreementClaimsHatter_HatClaimedWithAgreement(address claimer, uint256 hatId, bytes32 agreement);
  /// @dev Emitted when a user "signs" the `agreement` without claiming the hat
  event AgreementClaimsHatter_AgreementSigned(address signer, bytes32 agreement);
  /// @dev Emitted when a new `agreement` is set
  event AgreementClaimsHatter_AgreementSet(bytes32 agreement, uint256 grace);

  /*//////////////////////////////////////////////////////////////
                              CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /**
   * This contract is a clone with immutable args, which means that it is deployed with a set of
   * immutable storage variables (ie constants). Accessing these constants is cheaper than accessing
   * regular storage variables (such as those set on initialization of a typical EIP-1167 clone),
   * but requires a slightly different approach since they are read from calldata instead of storage.
   *
   * Below is a table of constants and their locations.
   *
   * For more, see here: https://github.com/Saw-mon-and-Natalie/clones-with-immutable-args
   *
   * ------------------------------------------------------------------------+
   * CLONE IMMUTABLE "STORAGE"                                               |
   * ------------------------------------------------------------------------|
   * Offset  | Constant            | Type      | Length | Source             |
   * ------------------------------------------------------------------------|
   * 0       | IMPLEMENTATION      | address   | 20     | HatsModule         |
   * 20      | HATS                | address   | 20     | HatsModule         |
   * 40      | hatId               | uint256   | 32     | HatsModule         |
   * 72      | OWNER_HAT           | uint256   | 32     | this               |
   * 104     | ARBITRATOR_HAT      | uint256   | 32     | this               |
   * ------------------------------------------------------------------------+
   */

  /// @notice The id of the hat whose wearer serves as the owner of this contract
  function OWNER_HAT() public pure returns (uint256) {
    return _getArgUint256(72);
  }

  /// @notice The id of the hat whose wearer serves as the arbitrator for this contract
  function ARBITRATOR_HAT() public pure returns (uint256) {
    return _getArgUint256(104);
  }

  /// @notice The minimum grace period for a new agreement
  uint256 public constant MIN_GRACE = 7 days;

  /*//////////////////////////////////////////////////////////////
                            MUTABLE STATE
  //////////////////////////////////////////////////////////////*/

  /// @notice The current agreement, as a hash of the agreement plaintext (likely a CID)
  bytes32 public agreement;

  /// @notice The timestamp at which the current grace period ends. Existing wearers of `hatId` have until this time to
  /// sign the current agreement.
  uint256 public graceEndsAt;

  /// @notice The most recent agreement that each wearer has signed
  mapping(address claimer => bytes32 agreement) public claimerAgreements;

  /// @notice The inverse of the standing of each wearer
  /// @dev Inversed so that wearers are in good standing by default
  mapping(address wearer => bool badStandings) public badStandings;

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /// @notice Deploy the implementation contract and set its version
  /// @dev This is only used to deploy the implementation contract, and should not be used to deploy clones
  constructor(string memory _version) HatsModule(_version) { }

  /*//////////////////////////////////////////////////////////////
                            INITIALIZER
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc HatsModule
  function setUp(bytes calldata _initData) public override initializer {
    uint256 _grace;
    (agreement, _grace) = abi.decode(_initData, (bytes32, uint256));
    if (_grace < MIN_GRACE) revert AgreementClaimsHatter_GraceTooShort();
    graceEndsAt = block.timestamp + _grace;
  }

  /*//////////////////////////////////////////////////////////////
                          PUBLIC FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Claim the `hatId` hat and sign the current agreement
   * @dev Mints the hat to the caller if they...
   *     - do already wear the hat, and
   *     - are not in bad standing for the hat.
   */
  function claimHatWithAgreement() public {
    bytes32 _agreement = agreement; // save SLOADs

    // we need to set the claimer's agreement before minting so that they are eligible for the hat on minting
    claimerAgreements[msg.sender] = _agreement;

    HATS().mintHat(hatId(), msg.sender);

    emit AgreementClaimsHatter_HatClaimedWithAgreement(msg.sender, hatId(), _agreement);
  }

  /**
   * @notice Sign the current agreement without claiming the hat. For users who have signed a previous agreement.
   * @dev Reverts if the caller has not already claimed the hat or has already signed the current agreement.
   */
  function signAgreement() public {
    bytes32 _agreement = agreement; // save SLOADs

    bytes32 _claimerAgreement = claimerAgreements[msg.sender]; // save SLOADs

    if (_claimerAgreement == bytes32(0)) revert AgreementClaimsHatter_HatNotClaimed();

    if (_claimerAgreement == _agreement) revert AgreementClaimsHatter_AlreadySigned();

    claimerAgreements[msg.sender] = _agreement;

    emit AgreementClaimsHatter_AgreementSigned(msg.sender, _agreement);
  }

  /*//////////////////////////////////////////////////////////////
                      HATS ELIGIBILITY FUNCTION
  //////////////////////////////////////////////////////////////*/

  /**
   * @inheritdoc IHatsEligibility
   * @dev Assumes that the only way _wearer has the hat is via {claimWithAgreement}. If they manage to get the hat some
   *  other way, this function will deem them to be eligible for the duration of the grace period, even if they have not
   *  signed the agreement. The benefit of this approach is cheaper gas cost compared to keeping track of the history of
   *  agreements and agreements signed by each wearer.
   */
  function getWearerStatus(address _wearer, uint256 /* _hatId */ )
    public
    view
    override
    returns (bool eligible, bool standing)
  {
    standing = !badStandings[_wearer];

    if (!standing) return (false, false);

    if (claimerAgreements[_wearer] == agreement) {
      eligible = true;
    } else if (block.timestamp < graceEndsAt) {
      eligible = true;
    }
  }

  /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Set a new agreement, with a grace period
   * @dev Only callable by a wearer of the `OWNER_HAT`
   * @param _agreement The new agreement, as a hash of the agreement plaintext (likely a CID)
   * @param _grace The new grace period; must be at least `MIN_GRACE` seconds and end after the current grace period
   */
  function setAgreement(bytes32 _agreement, uint256 _grace) public onlyOwner {
    uint256 _graceEndsAt = block.timestamp + _grace;

    if (_grace < MIN_GRACE) revert AgreementClaimsHatter_GraceTooShort();
    if (_graceEndsAt < graceEndsAt) revert AgreementClaimsHatter_GraceNotOver();

    graceEndsAt = _graceEndsAt;
    agreement = _agreement;

    emit AgreementClaimsHatter_AgreementSet(_agreement, _graceEndsAt);
  }

  /**
   * @notice Revoke the `_wearer`'s hat and place them in bad standing
   * @dev Only callable by a wearer of the `ARBITRATOR_HAT`
   */
  function revoke(address _wearer) public onlyArbitrator {
    // set bad standing in this contract
    badStandings[_wearer] = true;

    // revoke _wearer's hat and set their standing to false in Hats.sol
    HATS().setHatWearerStatus(hatId(), _wearer, false, false);

    /**
     * @dev Hats.sol will emit the following events:
     *   1. ERC1155.TransferSingle (burn)
     *   2. Hats.WearerStandingChanged
     */
  }

  /*//////////////////////////////////////////////////////////////
                            MODIFERS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Reverts if the caller is not wearing the member hat.
   */
  modifier onlyOwner() {
    if (!HATS().isWearerOfHat(msg.sender, OWNER_HAT())) revert AgreementClaimsHatter_NotOwner();
    _;
  }

  modifier onlyArbitrator() {
    if (!HATS().isWearerOfHat(msg.sender, ARBITRATOR_HAT())) revert AgreementClaimsHatter_NotArbitrator();
    _;
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import { console2 } from "forge-std/Test.sol"; // remove before deploy
import { HatsEligibilityModule, HatsModule, IHatsEligibility } from "hats-module/HatsEligibilityModule.sol";

contract AgreementClaimsHatter is HatsEligibilityModule {
  /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
  //////////////////////////////////////////////////////////////*/

  error AgreementClaimsHatter_NotOwner();
  error AgreementClaimsHatter_GraceTooShort();
  error AgreementClaimsHatter_GraceNotOver();
  error AgreementClaimsHatter_HatNotClaimed();
  error AgreementClaimsHatter_AlreadySigned();

  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  event HatClaimedWithAgreement(address claimer, uint256 hatId, bytes32 agreement);

  event AgreementSigned(address signer, bytes32 agreement);

  event AgreementSet(bytes32 agreement, uint256 grace);

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
   * 72      | AGEEMENT_SETTER_HAT | uint256   | 32     | this               |
   * ------------------------------------------------------------------------+
   */

  function OWNER_HAT() public pure returns (uint256) {
    return _getArgUint256(72);
  }

  uint256 public constant MIN_GRACE = 30 days;

  /*//////////////////////////////////////////////////////////////
                            MUTABLE STATE
  //////////////////////////////////////////////////////////////*/

  bytes32 public agreement;

  uint256 public graceEndsAt;

  mapping(address claimer => bytes32 agreement) public claimerAgreements;

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor(string memory _version) HatsModule(_version) { }

  /*//////////////////////////////////////////////////////////////
                            INITIALIZER
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc HatsModule
  function setUp(bytes calldata _initData) public override initializer {
    uint256 grace;
    (agreement, grace) = abi.decode(_initData, (bytes32, uint256));
    graceEndsAt = block.timestamp + grace;
  }

  /*//////////////////////////////////////////////////////////////
                          CLAIM FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function claimHatWithAgreement() public {
    HATS().mintHat(hatId(), msg.sender);

    bytes32 _agreement = agreement; // save SLOADs

    claimerAgreements[msg.sender] = _agreement;

    emit HatClaimedWithAgreement(msg.sender, hatId(), _agreement);
  }

  function signAgreement() public {
    bytes32 _agreement = agreement; // save SLOADs

    bytes32 _claimerAgreement = claimerAgreements[msg.sender]; // save SLOADs

    if (_claimerAgreement == hex"00") revert AgreementClaimsHatter_HatNotClaimed();

    if (_claimerAgreement == _agreement) revert AgreementClaimsHatter_AlreadySigned();

    claimerAgreements[msg.sender] = _agreement;

    emit AgreementSigned(msg.sender, _agreement);
  }

  /*//////////////////////////////////////////////////////////////
                      HATS ELIGIBILITY FUNCTION
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IHatsEligibility
  /// @dev Assumes that the only way _wearer has the hat is via {claimWithAgreement}. If they manage to get the hat some
  /// other way, this function will deem them to be eligible for the duration of the grace period, even if they have not
  /// signed the agreement. The benefit of this approach is cheaper gas cost compared to keeping track of the history of
  /// agreements and agreements signed by each wearer.
  function getWearerStatus(address _wearer, uint256 /* _hatId */ )
    public
    view
    override
    returns (bool eligible, bool standing)
  {
    if (claimerAgreements[_wearer] == agreement) {
      eligible = true;
    } else if (block.timestamp < graceEndsAt) {
      eligible = true;
    }
    standing = true;
  }

  /*//////////////////////////////////////////////////////////////
                          OWNER FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function setAgreement(bytes32 _agreement, uint256 _grace) public onlyOwner {
    uint256 _graceEndsAt = block.timestamp + _grace;

    if (_grace < MIN_GRACE || _graceEndsAt < graceEndsAt) revert AgreementClaimsHatter_GraceTooShort();

    graceEndsAt = _graceEndsAt;

    emit AgreementSet(_agreement, _graceEndsAt);
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
}

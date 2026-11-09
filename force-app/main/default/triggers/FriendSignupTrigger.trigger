trigger FriendSignupTrigger on Friend_Signup__e(after insert) {
  new FriendSignupTriggerHandler().run();
}

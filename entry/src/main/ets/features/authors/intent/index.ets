// L3 Feature - Authors - Intent barrel
export type {
  AuthorsIntent,
  AuthorsIntentKind,
  OpenAuthorProfileIntent,
  LoadRelatedAuthorsIntent,
  FollowAuthorIntent,
  UnfollowAuthorIntent,
  LoadFollowingAuthorsIntent,
  LoadAuthorReadingProgressIntent,
} from './AuthorsIntents';
export {
  AUTHORS_INTENT_KINDS,
  makeOpenAuthorProfileIntent,
  makeLoadRelatedAuthorsIntent,
  makeFollowAuthorIntent,
  makeUnfollowAuthorIntent,
  makeLoadFollowingAuthorsIntent,
  makeLoadAuthorReadingProgressIntent,
} from './AuthorsIntents';

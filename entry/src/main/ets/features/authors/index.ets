// L4 Feature - Authors - barrel
export { AuthorProfilePage } from './pages/AuthorProfilePage';
export { FollowingAuthorsPage } from './pages/FollowingAuthorsPage';
export { AuthorProfilePageAdapter } from './pages/AuthorProfilePageAdapter';
export type { AuthorsIntent, AuthorsIntentKind } from './intent/AuthorsIntents';
export {
  AUTHORS_INTENT_KINDS,
  makeOpenAuthorProfileIntent,
  makeLoadRelatedAuthorsIntent,
  makeFollowAuthorIntent,
  makeUnfollowAuthorIntent,
  makeLoadFollowingAuthorsIntent,
  makeLoadAuthorReadingProgressIntent,
} from './intent/AuthorsIntents';
export type { AuthorsData, AuthorsState } from './viewmodel/AuthorsViewModel';

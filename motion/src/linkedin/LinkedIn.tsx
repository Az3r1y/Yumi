import React from "react";
import { Reel } from "../Reel";
import { StoryLancement, StoryPermission } from "../stories/Stories";
import { Cadre } from "./Cadre";

// The LinkedIn cuts: the same films, framed at 4:5 for the feed.

/** The whole film, opening on the dark. */
export const LinkedInFilm: React.FC = () => (
  <Cadre>
    <Reel accroche="noir" />
  </Cadre>
);

/** A permission granted from the notch: the clip for developers. */
export const LinkedInPermission: React.FC = () => (
  <Cadre>
    <StoryPermission />
  </Cadre>
);

/** He wakes up in the notch. */
export const LinkedInLancement: React.FC = () => (
  <Cadre>
    <StoryLancement />
  </Cadre>
);

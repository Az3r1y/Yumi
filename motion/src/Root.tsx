import "./index.css";
import { Composition, Folder, Still } from "remotion";
import { Accroche } from "./scenes/Accroche";
import { Couverture } from "./scenes/Couverture";
import { Reel } from "./Reel";
import { Fin } from "./scenes/Fin";
import { Fonctions } from "./scenes/Fonctions";
import { Humeurs } from "./scenes/Humeurs";
import { StoryHumeurs, StoryLancement, StoryPermission, StorySalut, StoryYeux } from "./stories/Stories";
import { Pov } from "./scenes/Pov";
import { Planche } from "./scenes/Planche";
import { LinkedInFilm, LinkedInLancement, LinkedInPermission } from "./linkedin/LinkedIn";
import { MASTERCLASS_LENGTH, Masterclass } from "./linkedin/masterclass/Masterclass";
import { JOURNEE_LENGTH, Journee } from "./linkedin/journee/Journee";
import { JourneeEdito } from "./linkedin/journee/JourneeEdito";
import { BALADE_LENGTH, FondBalade, FondMatcha, MATCHA_LENGTH } from "./recap/Fonds";
import { ALPHA5_LENGTH, Alpha5En, Alpha5Fr } from "./recap/Alpha5";
import { REEL_LENGTH, RECAP_LENGTH, Recap, RecapEn, ReelEn, ReelFr } from "./recap/Recap";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="Reel-Instagram"
        component={Reel}
        durationInFrames={1656}
        fps={60}
        width={1080}
        height={1920}
        defaultProps={{ accroche: "noir" }}
      />
      <Composition
        id="Reel-TikTok"
        component={Reel}
        durationInFrames={1656}
        fps={60}
        width={1080}
        height={1920}
        defaultProps={{ accroche: "pov" }}
      />
      <Still id="Couverture" component={Couverture} width={1080} height={1920} />
      <Folder name="Stories">
        <Composition id="Story1-Yeux" component={StoryYeux} durationInFrames={270} fps={60} width={1080} height={1920} />
        <Composition id="Story2-Lancement" component={StoryLancement} durationInFrames={300} fps={60} width={1080} height={1920} />
        <Composition id="Story3-Permission" component={StoryPermission} durationInFrames={255} fps={60} width={1080} height={1920} />
        <Composition id="Story4-Humeurs" component={StoryHumeurs} durationInFrames={360} fps={60} width={1080} height={1920} />
        <Composition id="Story5-Salut" component={StorySalut} durationInFrames={300} fps={60} width={1080} height={1920} />
      </Folder>
      <Folder name="LinkedIn">
        <Composition id="LinkedIn-Journee-4x5" component={Journee} durationInFrames={Math.round(JOURNEE_LENGTH * 60)} fps={60} width={1080} height={1350} />
        <Composition id="LinkedIn-Journee-9x16" component={Journee} durationInFrames={Math.round(JOURNEE_LENGTH * 60)} fps={60} width={1080} height={1920} />
        <Composition id="LinkedIn-Journee-Edito-4x5" component={JourneeEdito} durationInFrames={Math.round(JOURNEE_LENGTH * 60)} fps={60} width={1080} height={1350} />
        <Composition id="LinkedIn-Journee-Edito-9x16" component={JourneeEdito} durationInFrames={Math.round(JOURNEE_LENGTH * 60)} fps={60} width={1080} height={1920} />
        <Composition id="Recap-16x9" component={Recap} durationInFrames={Math.round(RECAP_LENGTH * 60)} fps={60} width={1920} height={1080} />
        <Composition id="Recap-4x5" component={Recap} durationInFrames={Math.round(RECAP_LENGTH * 60)} fps={60} width={1080} height={1350} />
        <Composition id="Recap-EN-16x9" component={RecapEn} durationInFrames={Math.round(RECAP_LENGTH * 60)} fps={60} width={1920} height={1080} />
        <Composition id="Recap-EN-4x5" component={RecapEn} durationInFrames={Math.round(RECAP_LENGTH * 60)} fps={60} width={1080} height={1350} />
        <Composition id="Reel-FR-9x16" component={ReelFr} durationInFrames={Math.round(REEL_LENGTH * 60)} fps={60} width={1080} height={1920} />
        <Composition id="Alpha5-FR-9x16" component={Alpha5Fr} durationInFrames={Math.round(ALPHA5_LENGTH * 60)} fps={60} width={1080} height={1920} />
        <Composition id="Alpha5-FR-4x5" component={Alpha5Fr} durationInFrames={Math.round(ALPHA5_LENGTH * 60)} fps={60} width={1080} height={1350} />
        <Composition id="Alpha5-EN-9x16" component={Alpha5En} durationInFrames={Math.round(ALPHA5_LENGTH * 60)} fps={60} width={1080} height={1920} />
        <Composition id="Alpha5-EN-4x5" component={Alpha5En} durationInFrames={Math.round(ALPHA5_LENGTH * 60)} fps={60} width={1080} height={1350} />
        <Composition id="Fond-Balade-9x16" component={FondBalade} durationInFrames={Math.round(BALADE_LENGTH * 60)} fps={60} width={1080} height={1920} />
        <Composition id="Fond-Balade-16x9" component={FondBalade} durationInFrames={Math.round(BALADE_LENGTH * 60)} fps={60} width={1920} height={1080} />
        <Composition id="Fond-Matcha-9x16" component={FondMatcha} durationInFrames={Math.round(MATCHA_LENGTH * 60)} fps={60} width={1080} height={1920} />
        <Composition id="Fond-Matcha-16x9" component={FondMatcha} durationInFrames={Math.round(MATCHA_LENGTH * 60)} fps={60} width={1920} height={1080} />
        <Composition id="Reel-EN-9x16" component={ReelEn} durationInFrames={Math.round(REEL_LENGTH * 60)} fps={60} width={1080} height={1920} />
        <Composition id="Masterclass-16x9" component={Masterclass} durationInFrames={Math.round(MASTERCLASS_LENGTH * 60)} fps={60} width={1920} height={1080} />
        <Composition id="Masterclass-9x16" component={Masterclass} durationInFrames={Math.round(MASTERCLASS_LENGTH * 60)} fps={60} width={1080} height={1920} />
        <Composition id="LinkedIn-Film" component={LinkedInFilm} durationInFrames={1656} fps={60} width={1080} height={1350} />
        <Composition id="LinkedIn-Permission" component={LinkedInPermission} durationInFrames={255} fps={60} width={1080} height={1350} />
        <Composition id="LinkedIn-Lancement" component={LinkedInLancement} durationInFrames={300} fps={60} width={1080} height={1350} />
      </Folder>
      <Folder name="Plans">
        <Composition
          id="Accroche"
          component={Accroche}
          durationInFrames={300}
          fps={60}
          width={1080}
          height={1920}
        />
        <Composition
          id="Pov"
          component={Pov}
          durationInFrames={300}
          fps={60}
          width={1080}
          height={1920}
        />
        <Composition
          id="Fonctions"
          component={Fonctions}
          durationInFrames={954}
          fps={60}
          width={1080}
          height={1920}
        />
        <Composition
          id="Humeurs"
          component={Humeurs}
          durationInFrames={204}
          fps={60}
          width={1080}
          height={1920}
        />
        <Composition
          id="Fin"
          component={Fin}
          durationInFrames={198}
          fps={60}
          width={1080}
          height={1920}
        />
      </Folder>
      <Folder name="Reference">
        <Composition
          id="Planche"
          component={Planche}
          durationInFrames={240}
          fps={30}
          width={1920}
          height={1080}
        />
      </Folder>
    </>
  );
};

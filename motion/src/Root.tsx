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

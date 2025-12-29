---
title: Discovering a flaw in Minecraft data collection
date: 2025-11-05 14:10:00 -0500
render_with_liquid: true
---

During my work on my project Solaris, we needed to collect a dataset of Minecraft environment interactions to train our Minecraft video world model on. We chose Mineflayer as our data collection framework for its rich API of programmable Minecraft bots and access to the world state. Mineflayer has a plugin, [prismarine-viewer](https://github.com/PrismarineJS/prismarine-viewer), that provides observations. However, Mineflayer and its ecosystem don’t provide any built-in way to get the corresponding bot actions. At the end of the day, a world model dataset needs to have pairs of observations and actions.

## Studying an existing solution

We decided to use [LoopNav](https://github.com/Kevin-lkw/LoopNav)’s fork of the Mineflayer framework, released as part of [Toward Memory-Aided World Models: Benchmarking via Spatial Consistency](https://arxiv.org/abs/2505.22976v1), where the authors collected a dataset of navigation trajectories and had to address the same issue of not having the actions.

The problem with recording aligned actions and observations is that actions are processed and applied in the Mineflayer physics module, while observations are recorded in prismarine-viewer. To tie them together, LoopNav changed prismarine-viewer to record observations based on events from Mineflayer’s physics module rather than a constant time-based interval, and incorporated the latest action into the event. So, every time the viewer receives an event with an action, it renders the screen and thus forms a pair. You can see their commit [here](https://github.com/PrismarineJS/prismarine-viewer/compare/master...Kevin-lkw:prismarine-viewer:master).

It seemed like a pretty significant change to the rendering workflow, and to better study this mechanism, I added a debug timestamp recording at the time of action sending in the physics plugin: [commit](https://github.com/Kevin-lkw/mineflayer/compare/fd106c3afd2c66625937d591a2f5853dcd6f8ae9...fa7474e8ccb4d183ba9e698947650004ef63d42d?utm_source=chatgpt.com).

After collecting a test trajectory, I was confused because I saw consecutive frames with almost equal ms times (actionPTime is the timestamp field I added):

```json
   {
      "x":151.972,
      "y":80,
      "z":-106.052,
      "yaw":3.903,
      "pitch":0,
      "action":{
         "forward":false,
         "back":false,
         "left":false,
         "right":false,
         "jump":false,
         "sprint":false,
         "sneak":false,
         "camera":[
            -0.013089969389957545,
            0
         ]
      },
      "actionPTime":6425.70966,
      "frame_count":0
  }
```

You can see that the ms time almost doesn't change between the first and second frames, but changes between the second and the third. Digging deeper, I found that LoopNav captures actions in the physics module based on the physics tick, which is set to a 50ms constant interval — just like the original screen recording in prismarine-viewer — but also includes an auto-correction with multiple physics updates per tick if the machine runs slower. Here is the Mineflayer physics module [code](https://github.com/PrismarineJS/mineflayer/blob/master/lib/plugins/physics.js#L61-L76) that does it. LoopNav didn’t change this behavior and just hooked up their action sending to it. The autocorrection logic explains the almost equal actionPTime values I saw — these actions got recorded at the same physics tick.

## The action-observation delay issue

This got me thinking. If action recording and frame rendering are decoupled in LoopNav's implementation and action recording is kept at a constant rate of 1 action per 50ms via auto-correction, there is no guarantee that the prismarine-viewer listener can process the action events at the same 50ms frequency. In other words, the event queue publisher could have a higher throughput than the listener, leading to the observation rendering process lagging behind the action-producing process. To test it out, I added a renderPTime field with the timestamp at the time of rendering for the corresponding action in prismarine-viewer:

```json
[
	{
    "x": 204.547,
    "y": 70,
    "z": -32.345,
    "yaw": -3.196,
    "pitch": 0,
    "action": {
      "forward": true,
      "back": false,
      "left": false,
      "right": false,
      "jump": false,
      "sprint": false,
      "sneak": false,
      "camera": [0, 0]
    },
    "actionPTime": 33639.084674,
    "renderPTime": 41231.454631,
    "frame_count": 448
  },
  {
    "x": 204.542,
    "y": 70,
    "z": -32.194,
    "yaw": -3.196,
    "pitch": 0,
    "action": {
      "forward": true,
      "back": false,
      "left": false,
      "right": false,
      "jump": false,
      "sprint": false,
      "sneak": false,
      "camera": [0, 0]
    },
    "actionPTime": 33639.359034,
    "renderPTime": 41292.435758,
    "frame_count": 449
  },
  {
    "x": 204.537,
    "y": 70,
    "z": -32.014,
    "yaw": -3.212,
    "pitch": 0,
    "action": {
      "forward": false,
      "back": false,
      "left": false,
      "right": false,
      "jump": false,
      "sprint": false,
      "sneak": false,
      "camera": [-0.01570796326794799, 0]
    },
    "actionPTime": 33713.678584,
    "renderPTime": 41356.22668,
    "frame_count": 450
  }
]
```

The average time between consecutive renderPTime, i.e., the frequency at which the prismarine-viewer processes action events, was 70ms in my case. As the trajectory progressed into later frames (frame_count > 400), the time difference between when the action was sent from Mineflayer’s physics module and when the frame was rendered in prismarine-viewer reached around `7.5s`. This means that at the time of screen rendering, the action we assign to it as a pair is not the one that was just applied in the physics module, but the one 7.5s into the past.

## Movement-based experiment

I thought of conducting an experiment to visualize this observation-action delay. I made a Mineflayer bot that walks to a random location using the [pathfinder](https://github.com/PrismarineJS/mineflayer-pathfinder) plugin and then just walks to the left for 2s:

```javascript
      console.log("start task");
      move(botA, 60);
      bot.on("goal_reached", () => {
        console.log(`[${bot.username}] reached goal`);
        bot.setControlState("left", true);
        setTimeout(() => {
          bot.setControlState("left", false);
          console.log("ending");
          bot.emit("endtask");
        }, 2000);
      });
```

The endtask signal tells prismarine-viewer to stop recording. I expected the video to show the random walking part and then the strafe to the left, but the action file to only show the pathfinder walking (combination of forward and camera movements) without the strafe to the left part, since by the time we stop recording the queue of actions is big and we are truncating the queue at the actions we recorded 7.5s ago but with the most recent screen state. However, in reality, both the video and the actions file ended with the bot still being at the pathfinder walking stage. They both didn't show the full trajectory.

## World altering experiment

Investigating LoopNav’s change to prismarive-viewer, I found that they’d built their action event sending from the physics module to the viewer based on Mineflayer's packet mechanism for updating the bot's position on the viewer's screen. They kept the position update logic in the viewer and just hooked up screen rendering with action propagation to it: [code](https://github.com/Kevin-lkw/prismarine-viewer/blob/master/lib/headless.js#L105-L108). So, despite actions being recorded 7.5s in the past by the time the viewer gets to them, and the world actually looking different (the bot is strafing in the physics simulator), the viewer sets the bot position to the one in the packet/event, which is in the past, and then does the rendering. This makes recorded actions and rendered frames aligned but lagging behind together, i.e., the episode is truncated in both the video and the actions. I think LoopNav didn't notice any issue because their dataset contained only movements and only of a single bot. However, this approach will not work in the case there are more than one bot or if the bot is altering the world, i.e. mining or placing blocks because the packet the viewer uses to update bot's position on the screen doesn't contain any information about other players or the world so all other element of the environment will be rendered in their actual state (7.5s in the future from the recorded action perspective).

To confirm that I made another experiment. I made the bot walk, look at its feet, and then dig 5 blocks down:

{% include embed/youtube.html id='N-6hhD5yO00' %}

As you can see at the 8th second, the bot approaches the low ground, which already has a hole the bot dug up in the physics simulation, and the rendering is just catching up by resetting its position, but not the world state. LoopNav’s authors [confirmed](https://github.com/Kevin-lkw/LoopNav/issues/2#issuecomment-3314819964) that they only expected motion-based interaction with the environment and were unaware of this issue.

## A fully working solution

In my project, we needed a data collection system that would support multi-bot interaction and all possible actions in Minecraft. We couldn’t use LoopNav’s implementation, so we developed a time interval based recording solution within the viewer, similar to the original observation-only recording. The difference is that when we render, we query the current action state from the physics module and then save the combined pair. This way, frames and actions maintain their correlation, and rendering is decoupled from the physics simulation, so it doesn’t get reset to the past.

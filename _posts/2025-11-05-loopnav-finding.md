---
title: Discovering a flaw in Minecraft data collection
date: 2025-11-05 14:10:00 -0500
render_with_liquid: true
---

During my work on my project Solaris, we needed to collect a dataset of Minecraft environment interactions to train our Minecraft video world model on. We chose Mineflayer as our data collection framework for its rich API of programmable Minecraft bots and access to the world state. Mineflayer has a plugin, [prismarine-viewer](https://github.com/PrismarineJS/prismarine-viewer), that provides observations. However, Mineflayer and its ecosystem don’t provide any built-in way to get the corresponding bot actions. At the end of the day, a world model dataset needs to have pairs of observations and actions.

# Studying an existing solution


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

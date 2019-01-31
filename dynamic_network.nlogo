;;@author: Matt Nicholson

;; In this file, I am trying to make a model of a dynamic network. On this dynamic network, a color coordination task will happen. This will be the color matching game.
;; I think there should be one type of object, a node.

;; Right now each node changes in sequence, so the nodes at the end see
;; at some point need to think about how links can form ; make it consent based


extensions [
  ;csv
  table
  nw
]

breed [ nodes node ]
nodes-own [
  ;; Think about what variables need to be in here

  is-adversarial  ;; a int indication of whether or not a node is adversarial

  ; reputation information
  history-dict ;; a table of (other nodes, proportion-of-mismatch mismatch-count total-count)

  ; social information
  neighbor-counts ; like that one paper that showed people a picture of the network

  ; should I have somethng here to make them update once per time step? like right now it is kind of acting continuously because the later updates can see the first updates in the round
  last-time-color-changed ; to make a limit on how frequently one can change your color. Corresponds to posting limits (as it is on reddit)

  last-time-links-changed ; to make a limit on how dynamic the network is. Corresponds to friend request freeze (find some justification for this)

  ; should links be directed? no, but I'm going to add two-way consent to form a link
  who-i-will-link-with ; I think just a list for now a table of (other-nodes, next-I-will link with them). remove when they violate some conditions, like if the the proportion of color-mismatches exceeds the threshold


  ; should also come up with something for severing ties


]

directed-link-breed [edges edge]

globals [
 possible-colors ;; a list of all of the possible colors, should be of length number-of-colors
 coop-prop
 curr-prog
 last-mismatch-time
]


to setup
  show "starting setup"
  clear-all
  reset-ticks
  ask patches [
    set pcolor white
  ]

  set-default-shape nodes "circle"
  ;create-nodes number-of-nodes [set color blue]
  set last-mismatch-time 0

  link-formation

  node-setup

  ;; make a list of the possible colors
  set possible-colors (list 5)
  let color-loop-counter 1
  repeat number-of-colors - 1 [
    set possible-colors fput (color-loop-counter * 10 + 5) possible-colors
    set color-loop-counter color-loop-counter + 1
  ]


  layout ;; make it at least look pretty


end


to node-setup
  ask nodes [
    set color ((random number-of-colors) * 10 + 5)
    set label-color 0
    set size 2

    ;; maybe put an if statement here
    set history-dict table:make

    init-table self history-dict [0 0 0] ;; initialize table so each has a key for every other node and [prop color-mismatch-count total-count]
    ;; show history-dict

    set who-i-will-link-with table:keys history-dict ; to start, you will link to whoever
    ; set who-i-will-link-with table:make ;reconsider this maybe, but for now its just a list
    ; init-table self who-i-will-link-with 0
  ]
end

to layout
  layout-circle (sort nodes) max-pxcor - 3
end

to go

  if (not is-network-fixed)[
    ifelse (connection-strategy = "random") [ ;; maybe have one for adversaries and cooperators??
      ask nodes with [is-adversarial = 0][ ;; maybe put this on the outside of the switch statements
        connect-randomly ;; this is where I am going to have a big switch statement to pick different strategies
        disconnect-randomly
      ]

      ask nodes with [is-adversarial = 1][
        connect-randomly ;; this is where I am going to have a big switch statement to pick different strategies
        disconnect-randomly
      ]

      ] [ ; the else block
      if (connection-strategy = "reputation") [
        ask nodes with [is-adversarial = 0][
          connect-randomly
          disconnect-using-reputation self
        ]

        ask nodes with [is-adversarial = 1][
          connect-randomly ;; maybe make it so you have to consent to connect
          disconnect-randomly
        ]

      ]
    ]
  ]

  ask nodes with [is-adversarial = 0][ ;; maybe put this on the outside of the switch statements
    majority-vote-choose-color self  ;; this is where I am going to have a big switch statement to pick different strategies
    set label word "Coop:" color
  ]

  ask nodes with [is-adversarial = 1][
    majority-vote-choose-color self  ;; this is where I am going to have a big switch statement to pick different strategies
    set label word "Adver:" color
  ]


  tick

  ;; stopping conditions
  set coop-prop (count nodes with [is-adversarial = 0]) / (number-of-nodes)
  set curr-prog (count nodes with [is-adversarial = 0 and color = item 0 (modes [color] of nodes)]) / number-of-nodes

  if (curr-prog != coop-prop) [
    set last-mismatch-time ticks
    show curr-prog
    show coop-prop
  ]

  ifelse (last-mismatch-time < (ticks - 10)) [ ;; if you are all the same color for 10 ticks, you did it.
    show word "colors converged! after " ticks
    stop
    ] [
    if (ticks > 1000) [ ;; you took too long
      show "colors did not converge"
      stop
    ]

    ]

end


;;;;;;;;;;;;;;;;;;;;;;;;;;;; START OF HELPER FUNCTIONS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


to update-reputational-information [a-node]
  ; get all of the colors of the neighbors, if different, add one to my dictionary

  ask a-node [
    let my-color color

    let ids-to-increment [who] of link-neighbors

    foreach ids-to-increment [ x ->
      let history-list table:get history-dict x ; history-list is [prop color-mismatch total-count]

      let old-mismatch-count item 1 history-list
      let old-total-count item 2 history-list
      let new-mismatch-count old-mismatch-count

      if [color] of (node x) != my-color [
        set new-mismatch-count old-mismatch-count + 1
      ]

      let new-total-count old-total-count + 1

      let proportion-of-mismatch new-mismatch-count / new-total-count

      table:put history-dict x (list proportion-of-mismatch new-mismatch-count new-total-count)
    ]

    set who-i-will-link-with get-below-threshold-from-table history-dict color-mismatch-tolerance
    ;; show history-dict
  ]

end

;; writing these function to be intelligent is the hard part
to connect-randomly
  ;; change who they are connected to randomly
  let from-node (random number-of-nodes)
  let to-node (random number-of-nodes)

  ask node from-node [
    if (to-node != from-node and not (link-neighbor? node to-node) and (count link-neighbors <= max-links)) [

      if ((member? from-node [who-i-will-link-with] of (node to-node)) and (member? to-node who-i-will-link-with )) [ ;; only actually make the link if they both want it
        create-link-with node to-node
      ]
    ]
  ]
end

to disconnect-using-reputation [a-node]
  ; using the history-dict

  ask a-node [
    let bad-people-key get-top-n-from-table history-dict max-links

    foreach bad-people-key [suspected-bad-person ->
      remove-links-between (node who) (node suspected-bad-person)
    ]

  ]

end

to disconnect-randomly
  ;; change who they are connected to randomly
  remove-links-between (node (random number-of-nodes)) (node (random number-of-nodes))
end

to majority-vote-choose-color [a-node]

  let best-color [color] of a-node
  let worst-color [color] of a-node

  ask a-node [
    update-reputational-information self
    let node-neighbor-colors [color] of link-neighbors

    if (not empty? node-neighbor-colors)[

      set best-color item 0 (modes node-neighbor-colors)
      set worst-color one-of possible-colors;(best-color + 10) mod (number-of-colors * 10 + 5)

      ;show word "best color " best-color
      ;show word "worst color " worst-color
      ;show is-adversarial

      ifelse (is-adversarial = 1) [
        set color worst-color
      ] [ ;; this is the else block
        set color best-color
      ]
    ]
  ]

end


;;;;;;;;;;;;;;;;;; END OF HELPER FUNCTIONS and START OF UTILS ;;;;;;;;;;;;;;;;;;;;;;;;;;;

to link-formation
  if initial-network-structure = "disconnected"[
    show "nothing happens here, but it isnt a return so I'm printing"
    create-nodes number-of-adversarial [
      set shape "square" ;; squares are adversarial
      set is-adversarial true
    ]
    create-nodes number-of-nodes - number-of-adversarial [
      set is-adversarial false
    ]
  ]

  if initial-network-structure = "random" [
    nw:generate-random nodes links number-of-nodes ((number-of-nodes * number-of-links) / (number-of-nodes * (number-of-nodes - 1)))
    change-node-to-adversarial number-of-adversarial
  ]

  if initial-network-structure = "small-world" [
    nw:generate-watts-strogatz nodes links number-of-nodes number-of-links 0.3 ;;0.3 is the rewiring-probability
    change-node-to-adversarial number-of-adversarial
  ]
  if initial-network-structure = "regular" [
    nw:generate-watts-strogatz nodes links number-of-nodes number-of-links 0
    change-node-to-adversarial number-of-adversarial
  ]

  if initial-network-structure = "preferential"[
    ;; still need to change link-breed to direct, should I?? I think maybe no
    nw:generate-preferential-attachment nodes links number-of-nodes
    change-node-to-adversarial number-of-adversarial
  ]

end

to change-node-to-adversarial [n]
  ask n-of n nodes [
    set shape "square" ;; squares are adversarial
    set is-adversarial 1
    set size 2

    ]
end

to remove-links-between [ a b ]
   ask a [ ask my-links with [ other-end = b ] [ die ] ]
end


to init-table [a-node a-table init-val]
  ;; initializes the history dict with all the other nodes as a key and 0 for the value
  ;; show a-node
  let my-id who

  ask nodes with [who != my-id] [
    table:put a-table who init-val
  ]

  ; show a-table

end


to-report get-top-n-from-table [table n]
  ; returns a list of keys of the dictionary with the top n values

  let top-n-values sublist (sort-by > (map first table:values table)) 0 n

  let top-keys (list )

  foreach table:keys table [key ->
    let this-number first table:get table key

    ; show "this number"
    ; show this-numbernode

    if (member? this-number top-n-values) and (not member? key top-keys) [

      set top-keys fput key top-keys
    ]
  ]

  report top-keys

end


to-report get-below-threshold-from-table [table thresh]
  ; returns a list of keys of the dictionary where values are less than the threshold

  let below-keys (list )

  foreach table:keys table [key ->
    let this-number first table:get table key
    let ticks-connected last table:get table key

    let connect-time 10 ;; you have to be connected for 10 ticks to get blacklisted

    if (this-number < thresh or ticks-connected < connect-time) [ ;; if you have messed me up less than the allowable theshold or we haven't connected that much, you can still connectS
      set below-keys fput key below-keys
    ]

  ]

  report below-keys


end
@#$#@#$#@
GRAPHICS-WINDOW
444
10
938
505
-1
-1
6.0
1
10
1
1
1
0
0
0
1
-40
40
-40
40
1
1
1
ticks
30.0

SLIDER
3
43
175
76
number-of-nodes
number-of-nodes
3
100
100.0
1
1
NIL
HORIZONTAL

SLIDER
4
81
177
114
number-of-adversarial
number-of-adversarial
0
25
5.0
1
1
NIL
HORIZONTAL

BUTTON
888
12
951
45
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
1030
12
1093
45
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
954
12
1029
45
go once
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
4
117
176
150
number-of-colors
number-of-colors
1
13
13.0
1
1
NIL
HORIZONTAL

PLOT
908
106
1372
365
Proportion of matched colors
NIL
NIL
0.0
10.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot (count nodes with [is-adversarial = 0 and color = item 0 (modes [color] of nodes)]) / number-of-nodes "
"coop-proportion" 1.0 0 -14835848 true "" "plot (count nodes with [is-adversarial = 0]) / (number-of-nodes) \n"

MONITOR
907
57
978
102
NIL
count links
17
1
11

CHOOSER
11
153
168
198
initial-network-structure
initial-network-structure
"disconnected" "preferential" "small-world" "regular" "random"
1

SLIDER
5
202
177
235
number-of-links
number-of-links
0
20
4.0
1
1
NIL
HORIZONTAL

SWITCH
224
48
370
81
is-network-fixed
is-network-fixed
1
1
-1000

SWITCH
214
121
368
154
enforce-max-links
enforce-max-links
1
1
-1000

SLIDER
207
85
379
118
max-links
max-links
1
number-of-nodes
3.0
1
1
NIL
HORIZONTAL

TEXTBOX
206
10
403
68
In-game Params
24
0.0
1

CHOOSER
221
156
359
201
connection-strategy
connection-strategy
"random" "reputation"
0

CHOOSER
192
232
405
277
cooperator-color-change-strategy
cooperator-color-change-strategy
"majority vote"
0

CHOOSER
192
280
401
325
adversary-color-change-strategy
adversary-color-change-strategy
"anti majority vote"
0

TEXTBOX
262
36
350
54
Network params
11
0.0
1

TEXTBOX
253
218
403
236
Color params
11
0.0
1

TEXTBOX
35
15
185
33
Setup params
11
0.0
1

SLIDER
216
333
409
366
color-mismatch-tolerance
color-mismatch-tolerance
0
1
0.39
0.01
1
NIL
HORIZONTAL

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0.2
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@

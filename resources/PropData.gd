class_name PropData
extends Resource
## One prop the player can bring on a trip. Add a prop by creating a .tres with
## this script, pointing `behavior` at a script that extends Prop
## (see scenes/props/), and listing it in Garage.tscn.

enum Kind { PASSIVE, ACTIVE }

@export var id: StringName = &""
@export var display_name := ""
## One funny line for the garage.
@export_multiline var description := ""
## The rules, in a sentence or two (garage details panel).
@export_multiline var how_it_works := ""
@export var icon: Texture2D
## PASSIVE props work all trip; ACTIVE ones fire on the prop button.
@export var kind: Kind = Kind.ACTIVE
## Seconds after a use before it can be used again (active props).
@export var cooldown := 8.0
## Seconds one use lasts (0 = instant).
@export var duration := 0.0
## Script extending Prop that does the work during a race.
@export var behavior: Script

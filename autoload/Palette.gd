extends Node
## The one place colors live. Golden-hour Texas: warm, sun-bleached and a little
## desaturated. Saturated colors are reserved for things the player must notice
## (their car, cones and barrels, police lights).
##
## World meshes, the sky/fog/sun (see Atmosphere.gd) and the UI theme
## (see UiTheme.gd) all read from here, so tweaking a value re-tints the game.

# --- Sky and atmosphere -------------------------------------------------------
const SKY_TOP := Color(0.55, 0.69, 0.79)
const SKY_HORIZON := Color(0.91, 0.86, 0.77)
const FOG := Color(0.89, 0.85, 0.77)
const SUN := Color(1.0, 0.93, 0.8)
const AMBIENT := Color(0.66, 0.68, 0.7)

# --- Ground -------------------------------------------------------------------
const GRASS := Color(0.73, 0.7, 0.5)
const GRASS_DRY := Color(0.81, 0.76, 0.58)
const GRASS_DARK := Color(0.62, 0.62, 0.43)
const DIRT := Color(0.79, 0.65, 0.48)
const GRAVEL := Color(0.71, 0.66, 0.58)

# --- Road ---------------------------------------------------------------------
const ASPHALT := Color(0.47, 0.45, 0.43)
const SHOULDER := Color(0.56, 0.54, 0.5)
const LANE_WHITE := Color(0.95, 0.93, 0.88)
const LANE_YELLOW := Color(0.91, 0.76, 0.36)
const CONCRETE := Color(0.85, 0.82, 0.76)
const CONCRETE_SHADE := Color(0.74, 0.71, 0.65)

# --- Vegetation and roadside --------------------------------------------------
const LEAF := Color(0.49, 0.55, 0.31)
const LEAF_DARK := Color(0.41, 0.47, 0.25)
const LEAF_LIGHT := Color(0.58, 0.63, 0.36)
const TRUNK := Color(0.43, 0.35, 0.27)
const FENCE_POST := Color(0.54, 0.45, 0.38)
const WIRE := Color(0.36, 0.35, 0.33)
const POLE := Color(0.48, 0.42, 0.35)
const DELINEATOR := Color(0.95, 0.94, 0.9)

# --- Vehicles -----------------------------------------------------------------
const PLAYER_PAINT := Color(0.84, 0.31, 0.22)
# Garage paint choices (cosmetic). All saturated, so the player's car stays the
# loudest thing on the road whichever one you pick.
const PLAYER_PAINTS: Array[Color] = [
	Color(0.84, 0.31, 0.22),  # chili red
	Color(0.24, 0.45, 0.74),  # bluebonnet
	Color(0.13, 0.6, 0.58),   # gulf teal
	Color(0.42, 0.62, 0.22),  # jalapeño
	Color(0.53, 0.3, 0.66),   # grape soda
	Color(0.91, 0.45, 0.62),  # pink cadillac
]
const PLAYER_PAINT_NAMES: Array[String] = [
	"Chili Red", "Bluebonnet", "Gulf Teal", "Jalapeño", "Grape Soda", "Pink Cadillac",
]
const TIRE := Color(0.17, 0.17, 0.16)
const HUB := Color(0.79, 0.77, 0.73)
const TRIM := Color(0.27, 0.27, 0.27)
const GLASS := Color(0.23, 0.28, 0.32)
const HEADLIGHT := Color(1.0, 0.96, 0.85)
const TAILLIGHT := Color(0.85, 0.2, 0.16)
const AMBER := Color(1.0, 0.62, 0.16)

# Traffic paints are muted on purpose, so the player's car and the hazards stay
# the loudest things on screen. Levels can add a featured paint (LevelData).
const TRAFFIC_PAINTS: Array[Color] = [
	Color(0.92, 0.91, 0.88),  # white
	Color(0.74, 0.74, 0.72),  # silver
	Color(0.36, 0.37, 0.39),  # charcoal
	Color(0.48, 0.57, 0.66),  # dusty blue
	Color(0.6, 0.64, 0.53),   # sage
	Color(0.78, 0.7, 0.56),   # sand
	Color(0.52, 0.31, 0.31),  # faded burgundy
]
const TRAILER := Color(0.9, 0.89, 0.86)
const WORK_YELLOW := Color(0.93, 0.73, 0.22)

# --- Accents (reserved for gameplay-relevant things) ---------------------------
const CONE_ORANGE := Color(0.94, 0.48, 0.17)
const POLICE_RED := Color(0.89, 0.27, 0.24)
const POLICE_BLUE := Color(0.25, 0.44, 0.88)
const POLICE_BLACK := Color(0.11, 0.11, 0.12)
const SIGN_GREEN := Color(0.16, 0.42, 0.31)
const SIGN_WHITE := Color(0.96, 0.96, 0.93)

# --- UI -----------------------------------------------------------------------
const UI_PANEL := Color(0.98, 0.97, 0.94)
const UI_PANEL_DARK := Color(0.17, 0.16, 0.16)
const UI_TEXT := Color(0.17, 0.16, 0.16)
const UI_TEXT_LIGHT := Color(0.98, 0.97, 0.94)
const UI_ACCENT := Color(0.88, 0.33, 0.24)
const UI_MUTED := Color(0.55, 0.53, 0.49)
const UI_BONUS := Color(0.27, 0.58, 0.36)
const UI_WARN := Color(0.86, 0.24, 0.2)

class_name TouchControls
extends Node
## Mobile controls: on-screen pads for phone and tablet clients.
##
## When this client is a mobile one - and only then - the autoload evaluates a
## small page script (`OVERLAY_JS`) that lays a d-pad and the three verbs over
## the browser window. The pads send *keys*: every press dispatches a real
## KeyboardEvent to the canvas, which is what Godot's own web template wires
## its input listeners to. Everything the game polls through the action map
## therefore works unchanged, and so does every other consumer of genuine key
## events - attract mode hands the game over to a tap exactly the way it hands
## over to a keypress, and the pads cannot drift from the bindings because the
## keys they send have to exist in the input map (the suite checks that).
##
## Why a page overlay rather than buttons drawn inside Godot? The viewport is
## stretched to the game's 256x240 base with `keep` aspect, and CanvasItem
## content - including any CanvasLayer's - is clipped to that base rectangle
## even when the layer's transform cancels the stretch. Pads placed in the
## letterbox bars simply never appeared, which was verified against a
## phone-emulated Chromium, not assumed. The bars are exactly where thumbs
## rest on a landscape phone, so the pads have to live in the page.
##
## The head_include export option would have been the tidy way to ship a page
## fragment - in 4.7 it injects the option's literal string, not the file its
## value names, which is not a fragment worth maintaining in a .cfg - so the
## script travels inside the pck instead and runs through JavaScriptBridge
## once the engine is up. One source file, no export-time assembly step.
##
## The mobile question is asked once, here, so the title's legend and the
## presence of the pads cannot disagree. A touch-capable desktop monitor is
## not a mobile client, but an iPad pretending to be a desktop in its own
## Safari is.

## -1 decides by the client, 0 forces off, 1 forces on. Set from the command
## line, the environment, or directly by the suite.
static var force := -1

## Whether this client was decided to be a mobile one. The title screen reads
## this to swap its keyboard legend for a pads legend.
var active := false

## The probe that decides whether the browser is a mobile client. UA alone
## misses iPadOS, which sends a macOS UA by default, so the tablet is caught
## by the one thing a Mac does not have: touch points. Laptops with
## touchscreens report them too, but they also lack the mobile UA, and a
## laptop is exactly where the keyboard legend is still the truth.
##
## It is an expression, not statements, and it is evaluated with the global
## context flag: the engine's wrapped eval context returns `<null>` for code
## ending in a `return` in a no-threads export - which is what a GitHub Pages
## build has to be - while a global-context expression comes back as its
## string form. Both were verified against a phone-emulated Chromium.
const MOBILE_JS := """
String(/android|iphone|ipad|ipod|mobile/i.test(navigator.userAgent)
	|| (/Mac/i.test(navigator.platform) && navigator.maxTouchPoints > 1))
"""

## Whether the running client should get the on-screen controls.
static func is_mobile_client() -> bool:
	if force != -1:
		return force == 1
	if OS.has_feature("web"):
		return JavaScriptBridge.eval(MOBILE_JS, true) == "true"
	# Native builds: a touchscreen is a phone or tablet; a desktop's
	# emulated or absent one is not.
	return DisplayServer.is_touchscreen_available() and OS.has_feature("mobile")


## Command-line and environment overrides, so the headless suite and the CI
## scene boots can reach the mobile path without a mobile client.
static func _apply_overrides() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--touch-controls":
			force = 1
		elif arg == "--no-touch-controls":
			force = 0
	var env := OS.get_environment("TOUCH_CONTROLS")
	if env == "1":
		force = 1
	elif env == "0":
		force = 0


func _ready() -> void:
	_apply_overrides()
	active = is_mobile_client()
	if active and OS.has_feature("web"):
		JavaScriptBridge.eval(OVERLAY_JS, true)


## The page script: one d-pad low-left, jump big low-right, pepper beside it,
## pause in the top-right corner out of the way of play. Sizes are vmin so the
## pads land at the same physical size in both orientations, and the margins
## respect the notches via safe-area insets.
##
## Each pad owns one pointer id: setPointerCapture guarantees the release
## arrives even when the thumb has slid off the button, which is what a d-pad
## under a walking thumb needs. Every held key is also released on window
## blur, because a tab backgrounded under a thumb never sees its pointerup
## and the chef would walk into the next nasty on return.
const OVERLAY_JS := """
(function () {
	var canvas = document.getElementById("canvas") || document.querySelector("canvas");
	if (!canvas) { return; }
	var style = document.createElement("style");
	style.textContent = `
		#hh-touch{position:fixed;inset:0;pointer-events:none;touch-action:none;
			user-select:none;-webkit-user-select:none;-webkit-tap-highlight-color:transparent;
			z-index:10;font-family:sans-serif}
		.hh-pad{position:absolute;pointer-events:auto;touch-action:none;display:flex;
			align-items:center;justify-content:center;width:15vmin;height:15vmin;
			max-width:96px;max-height:96px;min-width:52px;min-height:52px;border-radius:50%;
			border:2px solid rgba(216,216,255,.3);background:rgba(235,235,255,.08);
			color:rgba(244,244,255,.6);font-size:6vmin;line-height:1}
		.hh-pad:active,.hh-pad.hh-held{border-color:rgba(216,216,255,.6);
			background:rgba(235,235,255,.18);color:rgba(244,244,255,.9)}
		#hh-up{bottom:calc(46vmin + env(safe-area-inset-bottom));left:calc(12vmin + env(safe-area-inset-left))}
		#hh-left{bottom:calc(30vmin + env(safe-area-inset-bottom));left:calc(4vmin + env(safe-area-inset-left))}
		#hh-right{bottom:calc(30vmin + env(safe-area-inset-bottom));left:calc(20vmin + env(safe-area-inset-left))}
		#hh-down{bottom:calc(14vmin + env(safe-area-inset-bottom));left:calc(12vmin + env(safe-area-inset-left))}
		#hh-jump{bottom:calc(4vmin + env(safe-area-inset-bottom));right:calc(4vmin + env(safe-area-inset-right));
			width:19vmin;height:19vmin;max-width:118px;max-height:118px}
		#hh-pepper{bottom:calc(24vmin + env(safe-area-inset-bottom));right:calc(14vmin + env(safe-area-inset-right))}
		#hh-pause{top:calc(4vmin + env(safe-area-inset-top));right:calc(4vmin + env(safe-area-inset-right));
			width:10vmin;height:10vmin;min-width:40px;min-height:40px;font-size:4vmin}
	`;
	document.head.appendChild(style);
	var root = document.createElement("div");
	root.id = "hh-touch";
	// Each pad is one button and one documented key. These codes are what
	// Godot's key listener reads off the event, and the suite checks they
	// still belong to the actions the input map binds.
	var pads = [
		["hh-left", "ArrowLeft", "\\u25C0"],
		["hh-right", "ArrowRight", "\\u25B6"],
		["hh-up", "ArrowUp", "\\u25B2"],
		["hh-down", "ArrowDown", "\\u25BC"],
		["hh-jump", "KeyX", "X"],
		["hh-pepper", "KeyF", "F"],
		["hh-pause", "KeyP", "II"],
	];
	var held = {};
	function keyEvent(type, code) {
		canvas.dispatchEvent(new KeyboardEvent(type, { code: code, key: code, bubbles: true }));
	}
	pads.forEach(function (pad) {
		var el = document.createElement("div");
		el.className = "hh-pad";
		el.id = pad[0];
		el.textContent = pad[2];
		el.setAttribute("aria-label", pad[1]);
		el.setAttribute("role", "button");
		root.appendChild(el);
		function press() {
			if (held[pad[0]]) { return; }
			held[pad[0]] = true;
			el.classList.add("hh-held");
			keyEvent("keydown", pad[1]);
		}
		function release() {
			if (!held[pad[0]]) { return; }
			delete held[pad[0]];
			el.classList.remove("hh-held");
			keyEvent("keyup", pad[1]);
		}
		el.addEventListener("pointerdown", function (ev) {
			ev.preventDefault();
			if (el.setPointerCapture && ev.pointerId !== undefined) { el.setPointerCapture(ev.pointerId); }
			press();
		});
		el.addEventListener("pointerup", function (ev) { ev.preventDefault(); release(); });
		el.addEventListener("pointercancel", release);
		el.addEventListener("lostpointercapture", release);
		el.addEventListener("contextmenu", function (ev) { ev.preventDefault(); });
	});
	window.addEventListener("blur", function () {
		Object.keys(held).forEach(function (id) {
			var pad = pads.find(function (p) { return p[0] === id; });
			delete held[id];
			var el = document.getElementById(id);
			if (el) { el.classList.remove("hh-held"); }
			if (pad) { keyEvent("keyup", pad[1]); }
		});
	});
	document.body.appendChild(root);
})()
"""

# Glecs - Godot Lightweight Entity Component System
Glecs is a set of [Godot](https://github.com/godotengine/godot) bindings for
the [Flecs](https://github.com/SanderMertens/flecs) entity component system via
GDExtension.

## Roadmap
- [ ] Expose more of the Flecs API.
	- [ ] TODO: Come up with list of API features that need adding.
- [ ] Support more systems
	- [ ] MacOS
	- [ ] Web
	- [ ] Android
	- [ ] IOS
- [ ] Add core entities that interface with Godot servers.
	- [ ] Rending 2D
	- [ ] Physics 2D
	- [ ] Rendering 3D
	- [ ] Physics 3D
	- [ ] Node-like entities
	- [ ] Resource-like entities
- [ ] Editor interface (Make Glecs feel like it's officially supported by Godot.)
	- [ ] Entity/tag/component inspector

## Branches

### [master](https://github.com/GsLogiMaker/godot-glecs)
The latest stable pre-compiled version of Glecs. This branch is updated
with every official release of Glecs.

To use this branch of Glecs in your Godot project open a terminal in
the `res://addons` folder and run the following command.
```bash
git clone https://github.com/GsLogiMaker/godot-glecs.git ./glecs/
```
Then activate Glecs in the plugins menu.

### [nightly](https://github.com/GsLogiMaker/godot-glecs/tree/nightly)
The latest un-stable pre-compiled version of Glecs. This branch is updated much
more frequently than `master`, changing whenever a push to the `dev` branch successfully
compiles and passes all unittests.

To use this branch of Glecs in your Godot project open a terminal in
the `res://addons` folder and run the following command.
```bash
git clone https://github.com/GsLogiMaker/godot-glecs.git ./glecs/ -b nightly
```
Then activate Glecs in the plugins menu.

### [dev](https://github.com/GsLogiMaker/godot-glecs/tree/dev)
The main development branch of glecs. This branch contains the raw c++ code
and unittests. To use this branch of Glecs in your Godot project, see the
build instructions below.

### [unittests-project](https://github.com/GsLogiMaker/godot-glecs/tree/unittests-project)
A Godot project setup to run Glecs unittests. Clone the branch with the
following command.
```bash
git clone https://github.com/GsLogiMaker/godot-glecs.git ./glecs-unittests/ -b unittests-project
```
Once cloned, you will need to clone Glecs to `res://addons/` yourself. Once you
have Glecs setup in the project, simple run the project in the editor to run
the unittests.

## Building
This section will help explain how to build Glecs from source.

### Requirements
Generally, if you follow the documentation to
[build Godot from source](https://docs.godotengine.org/en/stable/contributing/development/compiling/index.html)
you will be prepared to build Glecs too. Regardless, here is a short list of
software you will need to build Glecs from source.

- gcc
- python - 3.10
- scons - 4.0.1
- git

### Build
Clone the development branch. If you plan to use Glecs in a Godot project
clone it to `res://addons`.
```bash
git clone https://github.com/GsLogiMaker/godot-glecs.git ./glecs/ -b dev --recursive
```
Build Glecs's source code.
```bash
scons --directory godot-glecs/cpp
```
Once building is done, glecs will be ready to use in Godot. If you have cloned
Glecs to `res://addons` then the final step will be to enable the plugin in
Godot's plugin menu.

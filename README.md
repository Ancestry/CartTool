# CartTool

`carttool` can be used to perform some common tasks related to dependencies.

- Create a workspace with the current project and its dependencies.
- Switch a dependency to development mode so it can be modified and changes pushed upstream.
- Replace the `carthage copy-frameworks` build phase so you no longer have to list input & output files. 

## Installation

	sh build.sh
	cp .build/x86_64-apple-macosx10.10/release/carttool /usr/local/bin

## List Dependencies

	carttool list
	
The output is similar to the contents of `Cartfile.resolved`. One difference is that all repos are listed as an URL suitable for pasting into `git clone` or similar. 
	
## `copy-frameworks`

In place of the standard `carthage copy-frameworks` Run Script Build Phase, add a Build Phase with the script `carttool copy-frameworks`. You can omit the Input Files and Output Files. Just make sure the frameworks listed in Linked Frameworks and Libraries are correct. You only have to include direct dependencies in Linked Frameworks and Libraries. CartTool will take care of transitive dependencies. Do not include Carthage-built frameworks in Embedded Binaries.

`carttool copy-frameworks` will first look for frameworks in Derived Data, and then fall back to looking for frameworks under `Carthage/Build/<platform>`. This facilitates switching dependencies to "development mode". If you include a dependency in a workspace with your current project, the framework built from the workspace will be used instead of the Carthage-built framework. 

## Create a Workspace 

Create a workspace called `All.workspace` with the current project and all dependencies:

	carttool mkworkspace All
	
To create a workspace called `Foo.workspace` with the current project and two dependencies:

	carttool mkworkspace Foo Logger Authentication

`carttool mkworkspace` automates a few steps. You could accomplish the same thing by creating a new workspace and dragging in the current project as well as the projects under `Carthage/Checkouts/*`. You can drag in projects from other locations as well. For example, you might already have a dependency checked out in a different folder. You could delete a project reference (created by `carttool`) from the workspace and drag in your project from the other folder.

## Checkout a dependency for development

	cartool checkout Logger

This will clone the repo and leave it in a detached HEAD state at the ref found in `Cartfile.resolved`. At this point you probably want to `git checkout` an appropriate branch before proceeding rather than leave it in a detached HEAD state.

By using `carttool mkworkspace ...` and `carttool checkout ...` together. You can easily modify and commit/push dependencies. Make sure you update your `Cartfile` (or just `Cartfile.resolved` with a `carthage update Foo`) after you've pushed changes to a dependency.  

## Example Workflow

Let's say you're working on an app that uses `Authentication.framework`. You discover you need to make a change to `Authentication.framework`. You currently have the app project (not a workspace) open in Xcode. 

1. Close the project.
1. `carttool checkout Authentication`
1. `pushd Carthage/Checkouts/Authentication`
1. `git checkout master` (or use a git GUI of your choice)
1. `popd`
1. `carttool mkworkspace FixAuth Authentication`
1. `open FixAuth.xcworkspace`

Now you can make changes to `Authentication.framework` and test the changes by running your app. When you're finished making changes to the framework, 

1. Commit/push the changes to the Authentication repo.*
1. Tag/push (if needed).
1. Edit the `Cartfile` to point to the new tag (skip this step if it's already pointing to the correct branch).
1. `carthage update Authentication --platform iOS`
1. Commit changes to `Cartfile` and `Cartfile.resolved`. 
1. Close the workspace and switch back to the project. 
1. `rm -r FixAuth.xcworkspace` (if you want). 

`*`Keep in mind that there are two (or more) git repos in play. In addition the repo for the current project, there are also repos for any dependencies checked out with `carttool`. In the above example, `Carthage/Checkouts/Authentication` is a separate repo. Take care to commit & push to dependency repos before you commit & push changes to the current project that require the new dependency code. Make sure you're in the correct directory when performing `git` operations from the command line, or have multiple repos open in a GUI git client. 

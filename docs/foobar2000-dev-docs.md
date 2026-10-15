# foobar2000 Component Development — Documentación recopilada

Fuente: hydrogenaudio wiki (Development pages, vía web.archive.org) + SDK 2026-10-01.


## Overview

class="mw-body-content mw-content-ltr" lang="en" dir="ltr"> 
## What is a component
A foobar2000 component is a Windows Dynamic Link Library (DLL), or a Mac OS bundle with "component" extension, extending the functionality of the foobar2000 application.
A foobar2000 component implements one or more entrypoint services and interacts with services provided by foobar2000 core or other components.
Each component has a single exported DLL function, 
```
foobar2000_get_interface()
```
, called on startup to initialize and discover entrypoint services of your component. This function is generated automatically by the foobar2000_component_client module. Do not implement it yourself.
foobar2000 components are made using foobar2000 SDK and Microsoft Visual Studio or Xcode .
See also: Visual Studio Compatibility , SDK Contents .
## Packaging a component
Components are delivered to the user in form of fb2k-component file.
In old 32-bit foobar2000, this was originally a renamed zip of a component DLL.
In modern foobar2000, fb2k-component archive can contain multiple subdiretories with payloads for different processor architectures or operating systems.
If your component requires additional files, include them in the zip; foobar2000 will extract them to the folder containing your component DLL upon installation.
### Different architectures
Delivering as straightforward zip-of-a-DLL still works, but that leaves it up to the user to download the correct binary.
To support multiple CPU architectures with one package, put files meant for legacy x86 foobar2000 in top level and create subdirectories named after the architectures, with files that are specialized for those architectures. 
For an example, x64 foobar2000 will extract whole component archive, then overwrite files in root with those in x64 subfolder:
```
foo_sample.dll <= this is for legacy x86 foobar2000
x64\foo_sample.dll <= for x64 and arm64ec
arm64ec\foo_sample.dll <= arm64ec foobar2000 will prefer this over x64 if provided
mac\foo_sample.component <= Mac OS bundle
```
Components packaged this way will let foobar2000 choose the right thing to load.
The components site now accepts such components and detects supported CPU architectures by listing zip contents.
### Windows ARM support
foobar2000 for ARM is built in ARM64EC (Emulation Compatible) mode.
Because ARM64 Windows is still a niche platform, we cannot expect every developer to compile and test ARM64 components. foobar2000 for ARM64 is capable of seamlessly loading x64 components and transparently running them side by side with native components.
For non-performance-critical components, emulation of verified working x64 code is more than good enough, likely better than running untested ARM64 code if the developer has no means to test it.
See also: Foobar2000:Foobar2000 for ARM 
## Getting a component listed on foobar2000.org/components
Register a forum account and contact Peter with info about your component.
## Further reading
- Auto Pointers 
- Debugging 
- Exceptions 
- Global Callbacks: tracking foobar2000 lifetime events 
- SDK Contents 
- Services 
- Storing Configuration 
- Threads 
- Visual Studio Compatibility 


## SDK Contents

class="mw-body-content mw-content-ltr" lang="en" dir="ltr"> 
# Mandatory
Every component made with the foobar2000 SDK must link against these.
## foobar2000_SDK project
Contains declarations of services and various service-specific helper code.
This project defines how different parts of foobar2000 (core, components) interact with each other.
Every component must link against it.
## foobar2000_component_client project
Generates the DLL entrypoint function for your component, to allow foobar2000 to load and interact with your component.
Every component must link against it.
## shared.dll
Various utility code used by foobar2000 components. Mainly Win32 function wrappers working with UTF-8 strings instead of wchar_t, as foobar2000 uses UTF-8 strings internally.
This was once, before foobar2000 v0.9, called utf8api.dll and was specialized for Windows 9x (ANSI) and NT (Unicode), abstracting away the differences between the two and allowing the same foobar2000 components to run natively on both architectures. Most of it is no longer needed but preserved for backwards compatiblity with existing components.
Functions to interact with foobar2000 crash report writer are also implemented in shared.dll as they can't be using foobar2000 services, since they must be available before the services are initialized.
## PFC
A class library used by all other code.
Every component must link against it as foobar2000_SDK etc use it heavily.
# Optional
These are not required for building a working foobar2000 component, but you will probably want to use them anyway.
## foobar2000_SDK_helpers
A library of various helper code commonly used by foobar2000 components, such as cuesheet operations, tools to remember window positions using 
```
cfg_var
```
objects, helper classes for reading audio data from user's audio files.
This library now holds only code that is specific to foobar2000 / depends on foobar2000 SDK declarations one way or another. All code that can be used outside foobar2000 has been moved to libPPUI.
## libPPUI
A library of all helper code, mainly Windows UI code as the name implies, that is commonly used in foobar2000 but can be freely used in unrelated projects, that is does not depend on foobar2000 in any way.
libPPUI most notably includes CListControl, which implements the default playlist view of foobar2000.
libPPUI is released under a non-restrictive license. Reuse in other projects - including commercial projects - is encouraged. Credits in binary redistribution are not required.


## Services

class="mw-body-content mw-content-ltr" lang="en" dir="ltr"> 
## Services
A service type is an interface class, deriving directly or indirectly from service_base class. A service type class must not have any data members; it can only provide virtual methods (to be overridden by service implementation), helper non-virtual methods built around virtual methods, static helper methods, and constants / enums. Each service interface class must have a static class_guid member, used for identification when enumerating services or querying for supported functionality. A service type declaration should declare a class with public virtual/helper/static methods, and use 
```
FB2K_MAKE_SERVICE_INTERFACE() / FB2K_MAKE_SERVICE_INTERFACE_ENTRYPOINT()
```
macro to implement standard service behaviors for the class; additionally, class_guid needs to be defined outside class declaration (e.g. 
```
const GUID someclass::class_guid = {….};
```
). Note that most of components will not declare their own service types, they will only implement existing ones declared in the SDK.
A service implementation is a class derived from relevant service type class, implementing virtual methods declared by service type class. Note that service implementation class does not implement virtual methods declared by service_base; those are implemented automatically.
You cannot directly instantiate a service implementation object because it's still missing virtual methods of service_base.
```
class myworker : public threaded_process_callback { /* threaded_process_callback methods overridden here */ };
auto obj = new myworker; // error
auto obj = fb2k::service_new<myworker>(); // good
service_ptr_t<myworker> obj = new service_impl_t<myworker>; // longer equivalent of fb2k::service_new<>, commonly used in older code, not auto-friendly
```
fb2k::service_new<> takes care of implementing common methods (service_base) needed by all services and returns an autopointer object that manages reference counting for you.
Note that service_base methods:
- 
```
service_add_ref()
```
- 
```
service_release()
```
- 
```
service_query()
```
... are only intended for autopointer classes and should never be called directly in your code.
See also: Auto Pointers 
## Entrypoint services
An entrypoint service type is a special case of a service type that can be registered using service_factory templates, and then accessed from any point of service system (excluding DLL startup/shutdown code, such as code inside static object constructors/destructors). An entrypoint service type class must directly derive from service_base.
Registered entrypoint services can be accessed using:
- For services types with variable number of implementations registered: 
- 
```
enumerate()
```
static methods of the service class> 
```
for( auto ptr : someclass::enumerate() ) { /* do stuff with ptr */ }
```
- Or, 
```
service_enum_t<>
```
, commonly used in older code: 
```
service_enum_t<someclass> e; service_ptr_t<someclass> ptr; while(e.next(ptr)) ptr->dosomething();
```
- For services types with a single always-present implementation registered - such as core services like playlist_manager - using someclass::get(), e.g.: 
```
auto api = someclass::get(); api->dosomething(); api->dosomethingelse();
```
Using per-service-type defined static helper functions, e.g. 
```
someclass::g_dosomething()
```
- those use relevant service enumeration methods internally.
An entrypoint service type must use 
```
FB2K_MAKE_SERVICE_INTERFACE_ENTRYPOINT()
```
macro to implement standard entrypoint service behaviors, as opposed to all other service types that use 
```
FB2K_MAKE_SERVICE_INTERFACE()
```
macro instead.
You can register your own entrypoint service implementations using 
```
FB2K_SERVICE_FACTORY()
```
macro. It creates a static instance of your object and makes it available for everyone else to enumerate and access.
Some services need to be registered differently, see documentation of individual services for details.
A typical entrypoint service implementation looks like this:
```
class myinitquit : public initquit {
public:
void on_init() override {};
void on_quit() override {};
};
FB2K_SERVICE_FACTORY(myinitquit);
```
### Examples of entrypoint services
#### initquit, init_stage_callback
- Implemented by: everyone. 
- Called by: core, on app startup and shutdown. 
#### input_entry
- Implemented by: decoder components. 
- Called by: everyone decoding audio files. 
- This service is not implemented directly, but with help of 
```
input_factory_t<>
```
templates that implement all input services using your supplied class. 
#### playlist_loader
- Implemented by: core (standard playlist format), you (if you want to add your own playlist format). 
- Called by: any code loading or saving a playlist file. 
#### popup_message
- Implemented by: core. Do not reimplement! 
- Called by: everyone. 


## Storing Configuration

class="mw-body-content mw-content-ltr" lang="en" dir="ltr"> 
## Storing configuration
In order to create your entries in the foobar2000 configuration files, you must instantiate some objects that derive from 
```
cfg_var
```
class. Those can be either predefined classes (
```
cfg_int
```
, 
```
cfg_string
```
, etc) or your own classes implementing relevant methods.
Each 
```
cfg_var
```
instance has a GUID assigned, to identify its configuration file entry. The GUID is passed to its constructor (which implementations must take care of, typically by providing a constructor that takes a GUID and forwards it to 
```
cfg_var
```
constructor).
Note that 
```
cfg_var
```
objects can only be instantiated statically (either directly as static objects, or as members of other static objects).
It is encouraged to create your own configuration files in foobar2000 profile for more complex data to allow easy import / export / backup.


## Threads

class="mw-body-content mw-content-ltr" lang="en" dir="ltr"> 
## Thread safety
Programming interfaces of foobar2000 are either main-thread-only, or any-thread.
Refer to documentation in SDK headers of individual method or service to determine which of them it belongs to. If there's no mention of thread safety in the documentation, it means that it can be called from any thread.
In particular, any methods that take an 
```
abort_callback&
```
argument are obviously designed for use in worker threads, as main thread blocks the user interface and cannot be aborted.
If you have created an instance of some object, such as file or input_decoder, you should call its methods from one thread. If you must talk to one such object from multiple threads, synchronize access.
When in doubt about whether some API can be called off-main-thread, just try it. Methods that are designed for main thread use only will instantly crash (bugcheck) if called from another thread.
## Blocking main thread
Various operations, such as decoding of user's audio files, reading of network resources, reading of album covers, etc, can take a long time and block the calling thread.
Please do not do any of these things from the main thread if you can avoid it.
Create worker threads to do the job, then talk back to main thread using 
```
fb2k::inMainThread()
```
when done.
## fb2k::splitTask()
A special function exists to spawn detached worker threads that block foobar2000 shutdown (but not foobar2000 user interface) until finished.
Use 
```
fb2k::splitTask()
```
to create asynchronous tasks; if you don't provide your own 
```
abort_callback
```
, you can get shared one from 
```
async_task_manager::get()->get_aborter()
```
that will become signaled when foobar2000 is shutting down.
See SDK/app_close_blocker.h for more information.
## Scheduling code to run in main thread
You can defer any code to be executed in foobar2000's main thread using 
```
main_thread_callback
```
service. This is commonly used to update the user interface in response to progress/completion of asynchronous tasks.
Instead of using 
```
main_thread_callback
```
directly, use 
```
fb2k::inMainThread()
```
helper function to queue a function/lambda to be executed in main thread. This function returns immediately without blocking; if you need to wait for your main thread payload to execute, use other means (such as wait for an event).
If called in main thread, 
```
fb2k::inMainThread()
```
queues your code to be executed later in main thread. This can be used for an example to escape from the current context, avoiding race conditions when calling other foobar2000 API methods in response to global callbacks.
Another helper, 
```
fb2k::inMainThread2()
```
, executes your code synchronously if already in main thread, calls 
```
fb2k::inMainThread()
```
otherwise.
## Abortability
Various potentially timeconsuming methods take an 
```
abort_callback&
```
parameter to allow you to cancel them anytime.
When implementing such function, pass caller's 
```
abort_callback&
```
down to any other functions expecting one; poll the object often enough to react to user cancelling the operation without disturbing delays.
In case of user aborting the operation (such as stopping playback, cancelling ReplayGain scan, etc), the 
```
abort_callback
```
will become set and the next function to poll it will throw 
```
exception_aborted
```
, which then should be handled by the context that owns the 
```
abort_callback
```
object.
If you must call a function taking 
```
abort_callback&
```
and have no means to abort it, pass 
```
fb2k::noAbort
```
, the shared dummy 
```
abort_callback
```
object that never becomes aborted.


## Global Callbacks

class="mw-body-content mw-content-ltr" lang="en" dir="ltr"> 
## Tracking foobar2000 lifetime events: global callbacks
Multiple service classes presented by the SDK allow your component to receive notifications about various events.
We'll refer to these classes as global callbacks.
Essential examples of global callbacks:
- 
```
initquit
```
- notification about app startup and shutdown. 
- 
```
init_stage_callback
```
- more detailed notification about app startup and shutdown. 
- 
```
file_operation_callback
```
- tracking file move/copy/delete operations. 
- 
```
library_callback
```
- tracking Media Library content changes. 
- 
```
metadb_io_callback
```
- tracking tag read / write operations altering cached/displayed media information. 
- 
```
play_callback
```
- tracking playback related events. 
- 
```
playback_statistics_collector
```
- collecting information about played tracks. 
- 
```
playlist_callback
```
, 
```
playlist_callback_single
```
- tracking playlist changes (the latter tracks only active playlist changes). 
- 
```
playback_queue_callback
```
- tracking playback queue changes. 
- 
```
titleformat_config_callback
```
- tracking changes of title formatting configuration. 
- 
```
ui_drop_item_callback
```
- filtering items dropped into the UI. 
All of global callbacks operate only within main app thread, allowing easy cooperation with your user interface - for an example, you perform playlist view window repainting directly from your 
```
playlist_callback
```
implementation.
## Global callback recursion issues
There are restrictions on things that are legal to call from within global callbacks. For an example, you can't modify a playlist from inside a playlist callback, because there are other registered callbacks tracking playlist changes that haven't been notified about the change being currently processed yet.
You must not enter modal message loops from inside global callbacks, as those allow any unrelated code (queued messages, user input, etc.) to be executed, without being aware that a global callback is being processed. Certain global API methods such as 
```
metadb_io::load_info_multi
```
or 
```
threaded_process::run_modal
```
enter modal loops when called. Use 
```
main_thread_callback
```
service to avoid this problem and delay execution of problematic code.
You should also avoid firing a cross-thread 
```
SendMessage()
```
inside global callbacks as well as performing any operations that dispatch global callbacks when handling a message that was sent through a cross-thread 
```
SendMessage()
```
. Doing so may result in rare unwanted recursions - 
```
SendMessage()
```
call will block the calling thread and immediately process any incoming cross-thread 
```
SendMessage()
```
messages. If you're handling a cross-thread 
```
SendMessage()
```
and need to perform such operation, delay it using 
```
PostMessage()
```
or main_thread_callback.


## Auto Pointers

class="mw-body-content mw-content-ltr" lang="en" dir="ltr"> 
When performing most kinds of service operations, 
```
service_ptr_t<T>
```
template should be used instead of working with service pointers directly; it automatically manages reference counting, ensuring that the service object is deleted when it is no longer referenced.
For convenience, all service classes have 
```
myclass::ptr
```
typedef'd to 
```
service_ptr_t<myclass>
```
.
When working with pointers to core fb2k services, just use C++11 auto keyword and 
```
someclass::get()
```
, e.g. 
```
auto myAPI = playlist_manager::get();
```
service_ptr_t<> provides additional convenience operators:
- 
```
operator&=
```
Attempts to obtain a pointer to another interface, if the passed object supports it. Returns true on success, false on failure - interface not implemented or null pointer.
```
service_ptr_t<service1> A; 
service_ptr_t<service2> B;
A = create_service1();
if ( B &= A ) {
// B is valid.
// Do stuff with B.
} else {
// A does not implement service2, or is null.
}
```
- 
```
operator^=
```
Forced cast. Use to obtain a valid pointer to another interface in a scenario where you know that the object supports it. 
There's no error return, the process crashes if the interface you ask for is not implemented by this object.
```
service_ptr_t<service1> A; 
service_ptr_t<service2> B;
A = create_service1();
B ^= A;
// if you get here, B is valid (or null if A was null)
```
Use the above operators to safely cast from parent service class to derived service class. Do not use C++ 
```
dynamic_cast<> / static_cast<> / reinterpret_cast<>
```
on foobar2000 service classes.


## Exceptions

class="mw-body-content mw-content-ltr" lang="en" dir="ltr"> 
## Exception use
Most of API functions use C++ exceptions to signal failure conditions. All used exception classes must derive from 
```
std::exception
```
; this design allows various instances of code to use single 
```
catch()
```
line to obtain human-readable description of the problem to display.
Additionally, special subclasses of exceptions are defined for use in specific conditions, such as 
```
exception_io
```
for I/O failures. As a result, you must provide an exception handler whenever you invoke any kind of I/O code that may fail, unless in specific case calling context already handles exceptions (e.g. input implementation code - any exceptions should be forwarded to calling context, since exceptions are a part of input API).
Implementations of global callback services such as 
```
playlist_callback
```
, 
```
playback_callback
```
or 
```
library_callback
```
must not throw unhandled exceptions; behaviors in case they do are undefined (app termination is to be expected).

## Específico de macOS (headers del SDK 2026-10-01)

### DSP (foobar2000/SDK/dsp.h, dsp-frontend.h)
- Derivar de `dsp_impl_base` (`dsp_impl_base::on_chunk(audio_chunk*, abort_callback&)`; devolver true = pasar el chunk intacto).
- Métodos estáticos requeridos: `g_get_guid()`, `g_get_name(pfc::string_base&)`, `g_get_default_preset(dsp_preset&)`.
- Registrar con `static dsp_factory_t<T> g_xxx_factory;`.
- Popup de configuración en Mac: `g_show_config_popup(fb2k::hwnd_t, dsp_preset_edit_callback_v2::ptr)` (bajo `#ifdef __APPLE__`), devuelve `fb2k::wrapNSObject(NSViewController*)`.

### Panel de UI (foobar2000/SDK/ui_element.h, ui_element_mac.h)
- En Mac el panel deriva de `ui_element_mac` (declarado en ui_element_mac.h), NO de la versión Windows (ui_element).
- Métodos: `instantiate()`, `match_name()`, `get_name()`, `get_guid()`, `get_category()` (usar `ui_element_categories::playback` o similar).
- Registrar con `static service_factory_single_t<T> g_xxx_factory;`.
- El usuario lo agrega editando `UI-Layout.txt` del perfil (~/Library/foobar2000-v2/profile-.../UI-Layout.txt) poniendo el nombre del elemento.
- Ejemplo de referencia oficial: foo_sample/Mac/fooSampleDSPView.{h,mm,xib} (panel que visualiza un DSP) y foo_sample/ui_element_* en Windows; para Mac el ejemplo vivo es Stwarf/foo_dsp_macgeq.

### Plataforma (foobar2000/helpers-mac/, SDK/apple-tools.h, commonObjects-Apple.h)
- helpers-mac trae formateadores y utilidades Cocoa listas (fooDecibelFormatter, fooTimeFormatter, fooWindowWithCancel, fooPreferencesCommon).
- `apple-tools.h` / `commonObjects-Apple.h` exponen bridging fb2k<->Objective-C.

### Empaquetado multi-plataforma
- El .fb2k-component puede llevar `mac/foo_xxx.component` junto a los DLL de Windows; foobar2000 elige el payload correcto (mac/, x64/, arm64ec/).

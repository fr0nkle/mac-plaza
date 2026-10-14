#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmdeviceapi.h>
#include <audiopolicy.h>
#include <endpointvolume.h>
#include <node_api.h>
#include <memory>
#include <string>
#include <vector>
#include <unordered_map>
#include <algorithm>
#include <tlhelp32.h>
#define DISCORDPP_IMPLEMENTATION
#include "discordpp.h"

static std::shared_ptr<discordpp::Client> client;
static uint64_t generation=0,expectedUser=0;
static std::string discordState="disconnected";
struct Desktop { HWND oldParent; LONG_PTR style,exStyle; RECT rect; };
static std::unordered_map<HWND,Desktop> desktops;
static std::vector<DWORD> ourProcesses;
static bool ours(DWORD pid){return std::find(ourProcesses.begin(),ourProcesses.end(),pid)!=ourProcesses.end();}
static std::string processPath(DWORD pid){
  if(!pid||ours(pid))return{};HANDLE process=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,pid);if(!process)return{};
  wchar_t value[32768]{};DWORD length=32768;std::string result;
  if(QueryFullProcessImageNameW(process,0,value,&length)){int size=WideCharToMultiByte(CP_UTF8,0,value,length,nullptr,0,nullptr,nullptr);if(size>0){result.resize(size);WideCharToMultiByte(CP_UTF8,0,value,length,result.data(),size,nullptr,nullptr);}}
  CloseHandle(process);return result;
}
static napi_value fail(napi_env env,const char*message){napi_throw_error(env,nullptr,message);return nullptr;}
static napi_value string(napi_env env,const std::string&text){napi_value v;napi_create_string_utf8(env,text.c_str(),text.size(),&v);return v;}
static napi_value jsBoolean(napi_env env,bool value){napi_value v;napi_get_boolean(env,value,&v);return v;}
static std::string field(napi_env env,napi_value object,const char*name){napi_value v;if(napi_get_named_property(env,object,name,&v)!=napi_ok)return{};size_t n=0;if(napi_get_value_string_utf8(env,v,nullptr,0,&n)!=napi_ok||n>4096)return{};std::vector<char>bytes(n+1);napi_get_value_string_utf8(env,v,bytes.data(),bytes.size(),&n);return{bytes.data(),n};}
static std::string quoted(const std::string&value){std::string out="\"";for(unsigned char c:value){switch(c){case'"':out+="\\\"";break;case'\\':out+="\\\\";break;case'\n':out+="\\n";break;case'\r':out+="\\r";break;case'\t':out+="\\t";break;default:if(c>=32)out+=c;}}return out+'"';}
static void disconnect(){++generation;if(client)client->Disconnect();client.reset();expectedUser=0;discordState="disconnected";}
static napi_value configure(napi_env env,napi_callback_info info){
  size_t argc=1;napi_value args[1];napi_get_cb_info(env,info,&argc,args,nullptr,nullptr);if(argc!=1)return fail(env,"Missing Discord credentials.");
  auto application=field(env,args[0],"applicationID"),user=field(env,args[0],"discordID"),token=field(env,args[0],"accessToken");
  uint64_t applicationID;try{applicationID=std::stoull(application);expectedUser=std::stoull(user);}catch(...){return fail(env,"Invalid Discord identity.");}
  if(!applicationID||!expectedUser||token.empty())return fail(env,"Missing Discord credentials.");
  const auto own=expectedUser;disconnect();expectedUser=own;const auto current=++generation;
  client=std::make_shared<discordpp::Client>();client->SetApplicationId(applicationID);discordState="connecting";
  client->SetStatusChangedCallback([current](auto status,auto error,auto){if(current!=generation)return;discordState=status==discordpp::Client::Status::Ready?"ready":error!=discordpp::Client::Error::None?"authorization-required":"connecting";});
  client->UpdateToken(discordpp::AuthorizationTokenType::Bearer,token,[current](auto result){if(current!=generation||!client)return;if(result.Successful())client->Connect();else discordState="authorization-required";});
  return jsBoolean(env,true);
}
static napi_value pump(napi_env env,napi_callback_info){if(client)discordpp::RunCallbacks();return jsBoolean(env,true);}
static napi_value stop(napi_env env,napi_callback_info){disconnect();return jsBoolean(env,true);}
static napi_value snapshot(napi_env env,napi_callback_info){
  std::string friends="[";size_t count=0;
  if(client&&discordState=="ready"){
    auto self=client->GetCurrentUserV2();if(!self||self->Id()!=expectedUser){client->Disconnect();discordState="account-mismatch";}
    else for(const auto&relation:client->GetRelationships()){
      if(relation.DiscordRelationshipType()!=discordpp::RelationshipType::Friend)continue;
      auto user=relation.User();if(!user||!user->Id()||user->Status()==discordpp::StatusType::Blocked)continue;
      std::string presence="unknown";switch(user->Status()){case discordpp::StatusType::Online:presence="online";break;case discordpp::StatusType::Idle:presence="idle";break;case discordpp::StatusType::Dnd:presence="dnd";break;case discordpp::StatusType::Offline:case discordpp::StatusType::Invisible:presence="offline";break;default:break;}
      auto name=user->DisplayName();if(name.empty())name="Discord friend";
      if(count++)friends+=",";friends+="{\"discordID\":"+quoted(std::to_string(user->Id()))+",\"displayName\":"+quoted(name)+",\"presence\":"+quoted(presence)+"}";if(count>=1000)break;
    }
  }
  friends+="]";return string(env,"{\"state\":"+quoted(discordState)+",\"friends\":"+friends+"}");
}
static HWND handle(napi_env env,napi_callback_info info){size_t argc=1;napi_value args[1];napi_get_cb_info(env,info,&argc,args,nullptr,nullptr);void*data=nullptr;size_t size=0;if(argc!=1||napi_get_buffer_info(env,args[0],&data,&size)!=napi_ok||size!=sizeof(HWND))return nullptr;HWND window=*reinterpret_cast<HWND*>(data);DWORD pid=0;GetWindowThreadProcessId(window,&pid);return IsWindow(window)&&pid==GetCurrentProcessId()?window:nullptr;}
static BOOL CALLBACK iconHost(HWND candidate,LPARAM result){if(FindWindowExW(candidate,nullptr,L"SHELLDLL_DefView",nullptr)){*reinterpret_cast<HWND*>(result)=candidate;return FALSE;}return TRUE;}
static HWND desktopHost(){HWND host=nullptr;EnumWindows(iconHost,reinterpret_cast<LPARAM>(&host));if(host)return host;return FindWindowW(L"Progman",nullptr);}
static napi_value attach(napi_env env,napi_callback_info info){
  HWND window=handle(env,info);if(!window)return fail(env,"Invalid Plaza wallpaper window.");HWND host=desktopHost();if(!host)return fail(env,"Windows Explorer desktop is unavailable. Open the plaza in a window.");
  if(!desktops.count(window)){Desktop state{GetParent(window),GetWindowLongPtrW(window,GWL_STYLE),GetWindowLongPtrW(window,GWL_EXSTYLE),{}};GetWindowRect(window,&state.rect);desktops[window]=state;}
  SetLastError(0);if(!SetParent(window,host)&&GetLastError()!=0){desktops.erase(window);return fail(env,"Windows could not attach the wallpaper. Keep using the ordinary window.");}
  auto style=GetWindowLongPtrW(window,GWL_STYLE);SetWindowLongPtrW(window,GWL_STYLE,(style&~(WS_POPUP|WS_CAPTION|WS_THICKFRAME|WS_MINIMIZEBOX|WS_MAXIMIZEBOX))|WS_CHILD);
  auto exStyle=GetWindowLongPtrW(window,GWL_EXSTYLE);SetWindowLongPtrW(window,GWL_EXSTYLE,(exStyle&~WS_EX_APPWINDOW)|WS_EX_TOOLWINDOW);
  MONITORINFO monitor{sizeof(MONITORINFO)};GetMonitorInfoW(MonitorFromPoint(POINT{0,0},MONITOR_DEFAULTTOPRIMARY),&monitor);POINT point{monitor.rcMonitor.left,monitor.rcMonitor.top};MapWindowPoints(nullptr,host,&point,1);
  SetWindowPos(window,HWND_TOP,point.x,point.y,monitor.rcMonitor.right-monitor.rcMonitor.left,monitor.rcMonitor.bottom-monitor.rcMonitor.top,SWP_FRAMECHANGED|SWP_SHOWWINDOW|SWP_NOACTIVATE);
  return jsBoolean(env,true);
}
static napi_value detach(napi_env env,napi_callback_info info){HWND window=handle(env,info);auto found=desktops.find(window);if(found==desktops.end())return jsBoolean(env,false);auto state=found->second;SetParent(window,IsWindow(state.oldParent)?state.oldParent:nullptr);SetWindowLongPtrW(window,GWL_STYLE,state.style);SetWindowLongPtrW(window,GWL_EXSTYLE,state.exStyle);SetWindowPos(window,nullptr,state.rect.left,state.rect.top,state.rect.right-state.rect.left,state.rect.bottom-state.rect.top,SWP_FRAMECHANGED|SWP_NOZORDER|SWP_NOACTIVATE);desktops.erase(found);return jsBoolean(env,true);}
static napi_value desktopStatus(napi_env env,napi_callback_info info){
  HWND window=handle(env,info),host=desktopHost();RECT rect{};if(window)GetWindowRect(window,&rect);
  MONITORINFO monitor{sizeof(MONITORINFO)};GetMonitorInfoW(MonitorFromPoint(POINT{0,0},MONITOR_DEFAULTTOPRIMARY),&monitor);
  auto box=[](RECT r){return "["+std::to_string(r.left)+","+std::to_string(r.top)+","+std::to_string(r.right-r.left)+","+std::to_string(r.bottom-r.top)+"]";};
  return string(env,std::string("{\"attached\":")+(window&&desktops.count(window)&&GetParent(window)==host?"true":"false")+",\"hostAvailable\":"+(host?"true":"false")+",\"bounds\":"+box(rect)+",\"monitor\":"+box(monitor.rcMonitor)+"}");
}

template<class T>static void release(T*&object){if(object){object->Release();object=nullptr;}}
static bool otherAudio(EDataFlow flow){
  IMMDeviceEnumerator*enumerator=nullptr;IMMDevice*device=nullptr;IAudioSessionManager2*manager=nullptr;IAudioSessionEnumerator*sessions=nullptr;bool active=false;
  if(SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator),nullptr,CLSCTX_ALL,__uuidof(IMMDeviceEnumerator),reinterpret_cast<void**>(&enumerator)))&&SUCCEEDED(enumerator->GetDefaultAudioEndpoint(flow,eMultimedia,&device))&&SUCCEEDED(device->Activate(__uuidof(IAudioSessionManager2),CLSCTX_ALL,nullptr,reinterpret_cast<void**>(&manager)))&&SUCCEEDED(manager->GetSessionEnumerator(&sessions))){
    int count=0;sessions->GetCount(&count);for(int i=0;i<count&&!active;i++){IAudioSessionControl*control=nullptr;IAudioSessionControl2*control2=nullptr;IAudioMeterInformation*meter=nullptr;
      if(SUCCEEDED(sessions->GetSession(i,&control))&&SUCCEEDED(control->QueryInterface(__uuidof(IAudioSessionControl2),reinterpret_cast<void**>(&control2)))){DWORD pid=0;AudioSessionState state=AudioSessionStateInactive;control2->GetProcessId(&pid);control->GetState(&state);if(pid&&!ours(pid)&&state==AudioSessionStateActive){if(flow==eCapture)active=true;else if(SUCCEEDED(control->QueryInterface(__uuidof(IAudioMeterInformation),reinterpret_cast<void**>(&meter)))){float peak=0;meter->GetPeakValue(&peak);active=peak>0.0005f;}}}release(meter);release(control2);release(control);
    }
  }release(sessions);release(manager);release(device);release(enumerator);return active;
}
static napi_value environment(napi_env env,napi_callback_info info){
  std::unordered_map<DWORD,DWORD>parents;HANDLE list=CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0);if(list!=INVALID_HANDLE_VALUE){PROCESSENTRY32W entry{sizeof(PROCESSENTRY32W)};if(Process32FirstW(list,&entry))do{parents[entry.th32ProcessID]=entry.th32ParentProcessID;}while(Process32NextW(list,&entry));CloseHandle(list);}
  DWORD owner=GetCurrentProcessId();size_t argc=1;napi_value args[1];napi_get_cb_info(env,info,&argc,args,nullptr,nullptr);uint32_t candidate=0;
  if(argc==1&&napi_get_value_uint32(env,args[0],&candidate)==napi_ok&&candidate&&parents[owner]==candidate)owner=candidate;
  ourProcesses={owner};for(const auto&pair:parents){DWORD pid=pair.first;for(int depth=0;depth<6;depth++){auto p=parents.find(pid);if(p==parents.end())break;pid=p->second;if(pid==owner){ourProcesses.push_back(pair.first);break;}}}
  HWND foreground=GetForegroundWindow();DWORD pid=0;GetWindowThreadProcessId(foreground,&pid);bool covered=false;wchar_t name[128]{};GetClassNameW(foreground,name,128);
  if(!ours(pid)&&wcscmp(name,L"Progman")&&wcscmp(name,L"WorkerW")){RECT rect{};MONITORINFO monitor{sizeof(MONITORINFO)};if(GetWindowRect(foreground,&rect)&&GetMonitorInfoW(MonitorFromWindow(foreground,MONITOR_DEFAULTTONEAREST),&monitor)){const auto&m=monitor.rcMonitor;auto w=std::max(0L,std::min(rect.right,m.right)-std::max(rect.left,m.left)),h=std::max(0L,std::min(rect.bottom,m.bottom)-std::max(rect.top,m.top));covered=double(w)*h>=double(m.right-m.left)*(m.bottom-m.top)*0.85;}}
  return string(env,std::string("{\"otherAudio\":")+(otherAudio(eRender)||otherAudio(eCapture)?"true":"false")+",\"covered\":"+(covered?"true":"false")+",\"foreground\":"+quoted(processPath(pid))+"}");
}
static void cleanup(void*){disconnect();for(auto&pair:desktops){if(IsWindow(pair.first)){SetParent(pair.first,nullptr);SetWindowLongPtrW(pair.first,GWL_STYLE,pair.second.style);SetWindowLongPtrW(pair.first,GWL_EXSTYLE,pair.second.exStyle);}}desktops.clear();}
static napi_value init(napi_env env,napi_value exports){CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);napi_property_descriptor properties[]={
  {"configureDiscord",nullptr,configure,nullptr,nullptr,nullptr,napi_default,nullptr},{"pumpDiscord",nullptr,pump,nullptr,nullptr,nullptr,napi_default,nullptr},{"disconnectDiscord",nullptr,stop,nullptr,nullptr,nullptr,napi_default,nullptr},{"discordSnapshot",nullptr,snapshot,nullptr,nullptr,nullptr,napi_default,nullptr},
  {"attachWallpaper",nullptr,attach,nullptr,nullptr,nullptr,napi_default,nullptr},{"detachWallpaper",nullptr,detach,nullptr,nullptr,nullptr,napi_default,nullptr},{"wallpaperStatus",nullptr,desktopStatus,nullptr,nullptr,nullptr,napi_default,nullptr},{"environment",nullptr,environment,nullptr,nullptr,nullptr,napi_default,nullptr}};
  napi_define_properties(env,exports,sizeof(properties)/sizeof(properties[0]),properties);napi_add_env_cleanup_hook(env,cleanup,nullptr);return exports;}
NAPI_MODULE(NODE_GYP_MODULE_NAME,init)

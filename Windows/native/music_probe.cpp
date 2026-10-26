#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmdeviceapi.h>
#include <audiopolicy.h>
#include <endpointvolume.h>
#include <appmodel.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Media.Control.h>
#include <iostream>
#include <string>
#include <chrono>
using namespace winrt;
using namespace Windows::Media;
using namespace Windows::Media::Control;
static std::string quote(std::string const& value) {
  std::string out="\"";for(unsigned char c:value){if(c=='"'||c=='\\'){out+='\\';out+=c;}else if(c<32){char b[7];sprintf_s(b,"\\u%04x",c);out+=b;}else out+=c;}return out+'"';
}
// Read-only render observations: no metadata, capture devices or playback control.
static std::string audio() {
  com_ptr<IMMDeviceEnumerator> devices;check_hresult(CoCreateInstance(__uuidof(MMDeviceEnumerator),nullptr,CLSCTX_ALL,__uuidof(IMMDeviceEnumerator),devices.put_void()));
  com_ptr<IMMDeviceCollection> endpoints;check_hresult(devices->EnumAudioEndpoints(eRender,DEVICE_STATE_ACTIVE,endpoints.put()));
  UINT count=0;check_hresult(endpoints->GetCount(&count));std::string out="[";bool first=true;
  for(UINT i=0;i<count;i++)try{
    com_ptr<IMMDevice> device;check_hresult(endpoints->Item(i,device.put()));
    BOOL endpointMuted=FALSE;float endpointVolume=1;com_ptr<IAudioEndpointVolume> volume;
    check_hresult(device->Activate(__uuidof(IAudioEndpointVolume),CLSCTX_ALL,nullptr,volume.put_void()));
    check_hresult(volume->GetMute(&endpointMuted));check_hresult(volume->GetMasterVolumeLevelScalar(&endpointVolume));
    com_ptr<IAudioSessionManager2> manager;check_hresult(device->Activate(__uuidof(IAudioSessionManager2),CLSCTX_ALL,nullptr,manager.put_void()));
    com_ptr<IAudioSessionEnumerator> sessions;check_hresult(manager->GetSessionEnumerator(sessions.put()));int n=0;check_hresult(sessions->GetCount(&n));
    for(int j=0;j<n;j++)try{
      com_ptr<IAudioSessionControl> control;check_hresult(sessions->GetSession(j,control.put()));auto session=control.as<IAudioSessionControl2>();
      DWORD pid=0;AudioSessionState state;check_hresult(session->GetProcessId(&pid));check_hresult(session->GetState(&state));
      if(!pid||state!=AudioSessionStateActive||session->IsSystemSoundsSession()==S_OK)continue;
      float peak=0,level=0;BOOL muted=TRUE;check_hresult(control.as<IAudioMeterInformation>()->GetPeakValue(&peak));auto gain=control.as<ISimpleAudioVolume>();check_hresult(gain->GetMute(&muted));check_hresult(gain->GetMasterVolume(&level));
      HANDLE process=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,pid);if(!process)continue;
      wchar_t file[32768]={},appId[1024]={};DWORD size=32768;UINT32 idSize=1024;
      BOOL known=QueryFullProcessImageNameW(process,0,file,&size);LONG idResult=GetApplicationUserModelId(process,&idSize,appId);CloseHandle(process);if(!known)continue;
      std::wstring name(file);auto slash=name.find_last_of(L"\\/");if(slash!=std::wstring::npos)name=name.substr(slash+1);
      if(!first)out+=',';first=false;
      out+="{\"process\":"+quote(to_string(name))+",\"appId\":"+quote(idResult==ERROR_SUCCESS?to_string(appId):"")+",\"active\":true,\"muted\":"+((muted||endpointMuted||level<=0||endpointVolume<=0)?"true":"false")+",\"peak\":"+std::to_string(peak)+"}";
    }catch(...){}
  }catch(...){}
  return out+"]";
}
static std::string media(GlobalSystemMediaTransportControlsSessionManager const& manager){
  std::string out="[";bool first=true;
  for(auto const& session:manager.GetSessions())try{
    auto info=session.GetPlaybackInfo();auto type=info.PlaybackType();
    bool playing=info.PlaybackStatus()==GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing;
    bool music=type&&type.Value()==MediaPlaybackType::Music;
    if(!first)out+=',';first=false;
    out+="{\"appId\":"+quote(to_string(session.SourceAppUserModelId()))+",\"status\":"+quote(playing?"Playing":"NotPlaying")+",\"type\":"+quote(music?"Music":"UnknownOrNotMusic")+"}";
  }catch(...){}
  return out+"]";
}
int wmain(int argc,wchar_t** argv){
  bool once=argc<2||std::wstring(argv[1])==L"--once";
  HANDLE owner=once?nullptr:OpenProcess(SYNCHRONIZE,FALSE,wcstoul(argv[1],nullptr,10));if(!once&&!owner)return 1;
  try{
    init_apartment(apartment_type::multi_threaded);
    auto request=GlobalSystemMediaTransportControlsSessionManager::RequestAsync();
    if(request.wait_for(std::chrono::seconds(2))!=Windows::Foundation::AsyncStatus::Completed){request.Cancel();throw std::runtime_error("media unavailable");}
    auto manager=request.get();
    do{try{auto m=media(manager),a=audio();std::cout<<"{\"available\":true,\"media\":"<<m<<",\"audio\":"<<a<<"}"<<std::endl;}catch(...){std::cout<<"{\"available\":false,\"media\":[],\"audio\":[]}"<<std::endl;}
    }while(!once&&WaitForSingleObject(owner,500)==WAIT_TIMEOUT);
  }catch(...){std::cout<<"{\"available\":false,\"media\":[],\"audio\":[]}"<<std::endl;}
  if(owner)CloseHandle(owner);return 0;
}

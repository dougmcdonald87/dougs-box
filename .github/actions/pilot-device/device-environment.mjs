// The remote pairing agent must never inherit the privileged publication job environment.
const safeWindowsKeys = new Set([
 'PATH','PATHEXT','SYSTEMROOT','WINDIR','COMSPEC','TEMP','TMP','HOME','USERPROFILE',
 'APPDATA','LOCALAPPDATA','PROGRAMDATA','PROGRAMFILES','PROGRAMFILES(X86)','PUBLIC',
 'HOMEDRIVE','HOMEPATH','OS','USERNAME','USERDOMAIN',
 'PROCESSOR_ARCHITECTURE','NUMBER_OF_PROCESSORS'
]);
export function sandboxDeviceEnvironment(source=process.env) {
 const clean=Object.create(null);
 for(const [key,value] of Object.entries(source)) {
  if(safeWindowsKeys.has(key.toUpperCase()) && typeof value==='string')clean[key]=value;
 }
 return clean;
}

'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('vpn', {
  listServers: (force) => ipcRenderer.invoke('servers:list', !!force),
  connect: (args) => ipcRenderer.invoke('vpn:connect', args),
  disconnect: () => ipcRenderer.invoke('vpn:disconnect'),
  getStatus: () => ipcRenderer.invoke('vpn:getStatus'),
  publicIp: () => ipcRenderer.invoke('net:publicIp'),
  checkOpenVpn: () => ipcRenderer.invoke('openvpn:check'),
  openExternal: (url) => ipcRenderer.invoke('app:openExternal', url),
  onStatus: (cb) => {
    const listener = (_e, s) => cb(s);
    ipcRenderer.on('vpn:status', listener);
    return () => ipcRenderer.removeListener('vpn:status', listener);
  },
});

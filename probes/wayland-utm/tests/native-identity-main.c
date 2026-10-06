/* Origin: EmberBSD; AI-assisted production libdrm discovery assertions. */
/* SPDX-License-Identifier: BSD-2-Clause */
int main(void)
{
    drmDevicePtr devices[4]={0}, device=NULL;
    struct drm_native_pci_record record;
    char *name;
    assert(sizeof(record)==68);
    records[0]=(struct drm_native_pci_record){
        .version=1,.length=68,.flags=7,.bus_type=1,.domain=2,.bus=4,
        .device=3,.function=1,.vendor=0x1af4,.product=0x1050,
        .subvendor=0xabcd,.subproduct=0x1234,.revision=9,
        .primary_major=180,.primary_minor=3,.render_major=180,.render_minor=140
    };
    records[1]=records[0]; records[1].primary_minor=7; records[1].render_minor=129;
    records[1].bus=5; records[1].product=0x1051;
    /* No primary master or global device access exists in this fixture. */
    assert(drmGetDevices2(0,devices,4)==2);
    for(int i=0;i<2;i++) {
        assert(devices[i]->available_nodes==5);
        assert(devices[i]->deviceinfo.pci->vendor_id==0x1af4);
        assert(devices[i]->deviceinfo.pci->subvendor_id==0xabcd);
        assert(devices[i]->deviceinfo.pci->revision_id==0xff);
    }
    assert(!strcmp(devices[0]->nodes[2],"/dev/dri/renderD140"));
    assert(!strcmp(devices[1]->nodes[2],"/dev/dri/renderD129"));
    drmFreeDevices(devices,2);
    assert(drmGetDevice2(140,DRM_DEVICE_GET_PCI_REVISION,&device)==0);
    assert(device->businfo.pci->bus==4 && device->deviceinfo.pci->revision_id==9);
    drmFreeDevice(&device);
    assert(drmGetNodeTypeFromFd(140)==DRM_NODE_RENDER);
    assert(drmGetNodeTypeFromFd(3)==DRM_NODE_PRIMARY);
    name=drmGetRenderDeviceNameFromFd(3); assert(name && !strcmp(name,"/dev/dri/renderD140")); free(name);
    name=drmGetRenderDeviceNameFromFd(140); assert(name && !strcmp(name,"/dev/dri/renderD140")); free(name);
    assert(legacy_calls==0);
    assert(drmGetDevice2(140,2,&device)==-EINVAL && !device);
    assert(drmGetDevices2(2,devices,4)==-EINVAL);
    assert(drmGetDevice2(-1,0,&device)==-EINVAL);
    missing_render=true;
    assert(!drmGetRenderDeviceNameFromFd(3));
    assert(drmGetDevice2(140,0,&device)==-ENODEV);
    missing_render=false; reused_render=true;
    assert(!drmGetRenderDeviceNameFromFd(3));
    assert(drmGetDevice2(140,0,&device)==-ENODEV);
    reused_render=false;
    records[0].version=2;
    assert(drmNativeIdentity(180,140,&record)==-EPROTO);
    assert(drmGetDevice2(140,0,&device)<0);
    records[0].version=1; records[0].flags|=8;
    assert(drmNativeIdentity(180,140,&record)==-EPROTO);
    records[0].flags=7; returned_length=64;
    assert(drmNativeIdentity(180,140,&record)==-EPROTO); returned_length=68;
    records[0].flags=3;
    assert(drmGetDevice2(140,1,&device)==-ENODEV);
    assert(drmGetDevice2(140,0,&device)==0); drmFreeDevice(&device);
    records[0].flags=7;
    metadata_error=EACCES;
    assert(drmNativeIdentity(180,140,&record)==-EACCES); metadata_error=0;
    assert(legacy_calls==0);
    no_metadata=1;
    assert(drmGetDevice2(140,0,&device)<0 && legacy_calls>0);
    puts("PASS: production libdrm APIs, independent indices, folding, flags, missing/reused nodes, schema rejection and legacy fallback");
    return 0;
}

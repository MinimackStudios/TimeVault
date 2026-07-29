const path = require('node:path');

const mountPath = process.argv[2];
const dsStoreModulePath = process.argv[3];

if (!mountPath || !dsStoreModulePath) {
    throw new Error('Mounted DMG and ds-store module paths are required.');
}

const DSStore = require(path.resolve(dsStoreModulePath));
const store = new DSStore();

store.vSrn(1);
store.setIconSize(108);
store.setBackgroundPath(path.join(mountPath, '.background', 'dmg-background.tiff'));
store.setWindowPos(120, 120);
store.setWindowSize(660, 500);
store.setIconPos('TimeVault.app', 180, 135);
store.setIconPos('Applications', 480, 135);
store.setIconPos('Open TimeVault.command', 180, 340);
store.setIconPos('README.txt', 480, 340);

store.write(path.join(mountPath, '.DS_Store'), error => {
    if (error) {
        throw error;
    }
});

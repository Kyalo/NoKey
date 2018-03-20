const crypto = window.crypto || window.msCrypto;

/*// get a single random number
const getRandom32bitInt = () => {
    const randInt = new Uint32Array(1);
    crypto.getRandomValues(randInt);
    return randInt[0];
};
// Not usefull for elm, as the random library only uses 32bit anyway.
const getRandom53bitInt = () => {
    // get two cryptographically secure random ints
    const randInts = new Uint32Array(2);
    crypto.getRandomValues(randInts);


    // convert the two 32 bit ints to one 53 bit int (since that's the max number of bits for javascript ints)
    // taken from https://github.com/heap/cryptohat/blob/v1.0.1/index.js#L194
    const mask = Math.pow(2, 53 - 32) - 1;
    // NOTE: 4294967296 is Math.pow(2, 32). We inline the number to give V8 a
    //       better chance to implement the multiplication as << 32.
    return randInts[0] + (randInts[1] & mask) * 4294967296;
};*/



// check if we run inside an extension.
// TODO: possibly extend to detect android as well
const runsInsideExtension = () => {
    if (window.browser && browser.runtime && browser.runtime.id)
        return true;
    return false;
};


// returns a promise with two keys, [encryptionKey, signKey]
// TODO: call this if we haven't stored a key yet
// if there is an error anywhere, pass error along to elm inside flag to display error message
const genKeys = () => {
    // console.log("gen RSA-OAEP key: (encryption):");
    // TODO: should use this polyfill
    // https://github.com/PeculiarVentures/webcrypto-liner
    return Promise.all([
        crypto.subtle.generateKey({
            name: "RSA-OAEP",
            modulusLength: 2048,
            publicExponent: new Uint8Array([0x03]),
            hash: { name: "SHA-256" }
        }, true, ["encrypt", "decrypt"]),
        window.crypto.subtle.generateKey({
            name: "RSA-PSS",
            modulusLength: 2048,
            publicExponent: new Uint8Array([0x03]),
            hash: { name: "SHA-256" },
        }, true, ["sign", "verify"])
    ]);
};
// TODO: use the given key to encrypt the data.
// Use this via a port, to encrypt shares
const encrypt = (key, data) => {};
// should be used when we want to take out our share
const decrypt = (key, data) => {};

// TODO: sign a message with our key
// should be used in API, before we send out a message
const sign = (key, data) => {};
// should be used when we receive a message to check if it is authentic
const verify = (key, data) => {};





const storeState = (state, keys) => {
    const forStorageKeys = {
        encryptionKey: {
            exportedPublic: keys.encryptionKey.exportedPublic,
            exportedPrivate: keys.encryptionKey.exportedPrivate
        },
        signingKey: {
            exportedPublic: keys.signingKey.exportedPublic,
            exportedPrivate: keys.signingKey.exportedPrivate
        }
    };
    if (runsInsideExtension()) {
        browser.storage.local.set({ state: state, keys: forStorageKeys });
    } else {
        window.localStorage.setItem("state", JSON.stringify(state));
        window.localStorage.setItem("keys", JSON.stringify(forStorageKeys));
    }
};


const genNewKeys = (onGot) => {
    genKeys().then(([encryptionKey, signKey]) => {
        return Promise.all([
            crypto.subtle.exportKey("jwk", encryptionKey.privateKey),
            crypto.subtle.exportKey("jwk", encryptionKey.publicKey),
            crypto.subtle.exportKey("jwk", signKey.privateKey),
            crypto.subtle.exportKey("jwk", signKey.publicKey),
        ]).then(([encPr, encPu, signPr, signPu]) => {
            return {
                encryptionKey: {
                    public: encryptionKey.publicKey,
                    private: encryptionKey.privateKey,
                    exportedPublic: encPu,
                    exportedPrivate: encPr
                },
                signingKey: {
                    public: signKey.publicKey,
                    private: signKey.privateKey,
                    exportedPublic: signPu,
                    exportedPrivate: signPr
                }
            };
        });
    }).then((keys) => {
        onGot(keys);
    });
};


const genOrRestoreKeys = (state, keys, onGot) => {
    if (keys === null) {
        genNewKeys((keys) => {
            onGot(state, keys);
        });
    } else {
        importKeys(keys).then((myKeys) => {
            onGot(state, myKeys);
        });
    }
};

const importKeys = (keys) => {
    return Promise.all([
        window.crypto.subtle.importKey("jwk", keys.encryptionKey.exportedPublic, { name: "RSA-OAEP", hash: {name: "SHA-256"} }, true, ["encrypt"]),
        window.crypto.subtle.importKey("jwk", keys.encryptionKey.exportedPrivate, { name: "RSA-OAEP", hash: {name: "SHA-256"} }, true, ["decrypt"]),
        window.crypto.subtle.importKey("jwk", keys.signingKey.exportedPublic, { name: "RSA-PSS", hash: {name: "SHA-256"} }, true, ["verify"]),
        window.crypto.subtle.importKey("jwk", keys.signingKey.exportedPrivate, { name: "RSA-PSS", hash: {name: "SHA-256"} }, true, ["sign"])
    ]).then(([pubEnc, privDec, pubVery, privSign]) => {
        return {
            encryptionKey: {
                private: privDec,
                public: pubEnc,
                exportedPublic: keys.encryptionKey.exportedPublic,
                exportedPrivate: keys.encryptionKey.exportedPrivate
            },
            signingKey: {
                private: privSign,
                public: pubVery,
                exportedPublic: keys.signingKey.exportedPublic,
                exportedPrivate: keys.signingKey.exportedPrivate
            }
        };
    });
};



const getState = (onGot) => {
    if (runsInsideExtension()) {
        browser.storage.local.get({state: null, keys: null})
            .then((state) => genOrRestoreKeys(state.state, state.keys, onGot))
            .catch(() => {
                console.error("couldn't get storage!");
            });
    } else {
        const state = window.localStorage.getItem("state");
        const keys = window.localStorage.getItem("keys");
        if (state !== null) {
            if (keys !== null) {
                genOrRestoreKeys(JSON.parse(state), JSON.parse(keys), onGot);
            } else {
                genOrRestoreKeys(JSON.parse(state), null, onGot);
            }
        } else {
            genOrRestoreKeys(null, null, onGot);
        }
    }

};

// reset storage, and store the newly provided state.
// This keeps the old keys (since the 'old' device no longer exists)
const resetStorage = (state, keys) => {
    if (runsInsideExtension()) {
        browser.storage.local.clear();
    } else {
        window.localStorage.clear();
    }
    storeState(state, keys);
};



const getRandomInts = (n) => {
    const randInts = new Uint32Array(n);
    crypto.getRandomValues(randInts);
    return Array.from(randInts);
};



const setup = (startFn, onStart) => {
    getState((state, keys) => {
        // console.log("stored state: ", state);

        // 1 + 8 32bit ints give us a generator of period (2^32)^9bits, which corresponds to (2^8)^36bit,
        // e.g. more than enough for 32 character passwords.
        const rands = getRandomInts(9);

        // TODO: add android
        let deviceType = "Browser";
        if (runsInsideExtension()) {
            deviceType = "WebExtension";
        }

        const flags = {
            initialSeed: [rands[0], rands.slice(1)],
            storedState: state,
            encryptionKey: keys.encryptionKey.exportedPublic,
            signingKey: keys.signingKey.exportedPrivate,
            deviceType: deviceType
        };

        // console.log(flags);
        const app = startFn(flags);

        app.ports.setTitle.subscribe((title) => {
            document.title = title;
        });


        app.ports.storeState.subscribe((state) => {
            // console.log("store state: ", state);
            storeState(state, keys);
        });

        app.ports.resetStorage.subscribe((state) => {
            resetStorage(state, keys);
        });

        if (onStart) {
            onStart(app);
        }
    });
};


if (typeof module === 'undefined') {
    module = {};
}
module.exports = {
    setup: setup,
    getRandomInts: getRandomInts,
    runsInsideExtension: runsInsideExtension
};

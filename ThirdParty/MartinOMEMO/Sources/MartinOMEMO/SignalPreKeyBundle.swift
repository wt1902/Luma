//
// SignalPreKeyBundle.swift
//
// TigaseSwift OMEMO
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see https://www.gnu.org/licenses/.
//

import Foundation
import libsignal

public class SignalPreKeyBundle {
    
    let bundle: OpaquePointer;
    
    public convenience init?(registrationId: UInt32, deviceId: Int32, preKey: OMEMOModule.OMEMOPreKey, bundle: OMEMOModule.OMEMOBundle) {
        self.init(
            registrationId: registrationId,
            deviceId: deviceId,
            preKeyId: preKey.preKeyId,
            preKeyPublic: preKey.data,
            signedPreKeyId: bundle.signedPreKeyId,
            signedPreKeyPublic: bundle.signedPreKeyPublic,
            signedPreKeySignature: bundle.signature,
            identityKey: bundle.identityKey
        )
    }

    /// Raw-data initializer added by Luma so an OMEMO 2 bundle (the
    /// `urn:xmpp:omemo:2` format) can be turned into a Signal prekey bundle
    /// without routing through the legacy bundle types.
    public init?(
        registrationId: UInt32,
        deviceId: Int32,
        preKeyId: UInt32,
        preKeyPublic: Data,
        signedPreKeyId: UInt32,
        signedPreKeyPublic: Data,
        signedPreKeySignature: Data,
        identityKey: Data
    ) {
        guard let preKeyPublicKey = SignalIdentityKey.publicKey(from: preKeyPublic) else {
            return nil;
        }
        guard let signedPreKeyPublicKey = SignalIdentityKey.publicKey(from: signedPreKeyPublic) else {
            signal_type_unref(preKeyPublicKey);
            return nil;
        }
        guard let identityKeyKey = SignalIdentityKey.publicKey(from: identityKey) else {
            signal_type_unref(preKeyPublicKey);
            signal_type_unref(signedPreKeyPublicKey);
            return nil;
        }
        
        var bundlePtr: OpaquePointer?;
        guard signedPreKeySignature.withUnsafeBytes({ (bytes) -> Bool in
            let result = session_pre_key_bundle_create(&bundlePtr, registrationId, deviceId, preKeyId, preKeyPublicKey, signedPreKeyId, signedPreKeyPublicKey, bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), signedPreKeySignature.count, identityKeyKey);
            signal_type_unref(preKeyPublicKey);
            signal_type_unref(signedPreKeyPublicKey);
            signal_type_unref(identityKeyKey);
            
            return result >= 0;
        }) else {
            return nil;
        }
        
        self.bundle = bundlePtr!;
    }
 
    deinit {
        signal_type_unref(bundle);
    }
    
}

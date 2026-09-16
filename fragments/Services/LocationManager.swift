//
//  LocationManager.swift
//  fragments
//
//  Created on 9/16/26.
//

import Foundation
import CoreLocation
import Observation

@Observable
public final class LocationManager: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    public static let shared = LocationManager()

    public var currentLocationName: String? = nil
    public var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()

    public override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        self.authorizationStatus = locationManager.authorizationStatus
        #if !targetEnvironment(simulator)
        requestLocation()
        #else
        self.currentLocationName = "Sanur Beach, Bali"
        #endif
    }

    public func requestLocation() {
        #if targetEnvironment(simulator)
        self.currentLocationName = "Sanur Beach, Bali"
        #else
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.requestLocation()
        }
        #endif
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        DispatchQueue.main.async {
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self, error == nil, let placemark = placemarks?.first else { return }

            let city = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
            let countryCode = placemark.isoCountryCode

            let name: String
            if let c = city, let cc = countryCode {
                name = "\(c), \(cc)"
            } else if let c = city {
                name = c
            } else if let country = placemark.country {
                name = country
            } else {
                name = "Current Location"
            }

            DispatchQueue.main.async {
                self.currentLocationName = name
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationManager error: \(error.localizedDescription)")
    }
}

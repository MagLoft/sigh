require 'spaceship'

module Sigh
  class Runner
    attr_accessor :spaceship

    # Uses the spaceship to create or download a provisioning profile
    # returns the path the newly created provisioning profile (in /tmp usually)
    def run
      Spaceship.login(Sigh.config[:username], nil)
      Spaceship.client.select_team
      
      profiles = fetch_profiles # download the profile if it's there

      if profiles.count > 0
        Helper.log.info "Found #{profiles.count} profiles, downloading the first one".yellow if profiles.count > 1
        profile = profiles.first
      else
        Helper.log.info "No existing profiles found, creating a new one for you".yellow
        profile = create_profile!
        # We don't want to use the return value here, as this doesn't include all the information we need
        profile = fetch_profiles.first # better fetch it frmo the server again
      end

      if Sigh.config[:force]
        unless profile_type == Spaceship::ProvisioningProfile::AppStore
          Helper.log.info "Updating the profile to include all devices".yellow
          profile.devices = Spaceship.devices          
        end

        profile.update!
        profile = fetch_profiles.first # to have the latest profile information
      end
      
      path = download_profile(profile)
      store_provisioning_id_in_environment(path)

      return path
    end

    # The kind of provisioning profile we're interested in
    def profile_type
      return @profile_type if @profile_type

      @profile_type = Spaceship::ProvisioningProfile::AppStore
      @profile_type = Spaceship::ProvisioningProfile::AdHoc if Sigh.config[:adhoc]
      @profile_type = Spaceship::ProvisioningProfile::Development if Sigh.config[:development]

      @profile_type
    end

    # Fetches a profile matching the user's search requirements
    def fetch_profiles
      profile_type.all.select do |profile|
        
        # Does the app identifier match
        next unless (profile.app.bundle_id == Sigh.config[:app_identifier])

        true
      end
    end

    # Create a new profile and return it
    def create_profile!
      cert = certificate_to_use
      bundle_id = Sigh.config[:app_identifier]
      name = Sigh.config[:provisioning_name] || [bundle_id, profile_type.pretty_type].join(' ')

      if Spaceship::ProvisioningProfile.all.find { |p| p.name == name }
        Helper.log.error "The name '#{name}' is already taken, using another one."
        name += " #{Time.now.to_i}"
      end

      Helper.log.info "Creating new provisioning profile for '#{Sigh.config[:app_identifier]}' with name '#{name}'".yellow
      profile = profile_type.create!(name: name, 
                                bundle_id: bundle_id,
                              certificate: cert)
      profile
    end


    # Certificate to use based on the current distribution mode
    def certificate_to_use
      if profile_type == Spaceship::ProvisioningProfile::Development
        certificates = Spaceship::Certificate::Development.all
      else
        certificates = Spaceship::Certificate::Production.all # Ad hoc or App Store
      end

      if certificates.count > 1
        Helper.log.info "Found more than one code signing identity. Choosing the first one. Check out `sigh --help` to see all available options.".yellow
      end
      if certificates.count == 0
        raise "Could not find a matching code signing identity for #{profile_type}. You can use cert to generate one (https://github.com/fastlane/cert)"
      end

      return certificates.first
    end

    # Downloads and stores the provisioning profile
    def download_profile(profile)
      Helper.log.info "Downloading provisioning profile...".yellow

      profile_name ||= "#{profile.class.pretty_type}_#{Sigh.config[:app_identifier]}.mobileprovision" # default name
      profile_name += '.mobileprovision' unless profile_name.include?'mobileprovision'

      output_path = File.join('/tmp', profile_name)
      dataWritten = File.open(output_path, "wb") do |f|
        f.write(profile.download)
      end

      Helper.log.info "Successfully downloaded provisioning profile...".green
      return output_path
    end

    # Store the profile ID into the environment
    def store_provisioning_id_in_environment(path)
      require 'sigh/profile_analyser'
      udid = Sigh::ProfileAnalyser.run(path)
      ENV["SIGH_UDID"] = udid if udid
    end
  end
end
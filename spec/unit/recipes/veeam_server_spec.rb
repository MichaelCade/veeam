#
# Cookbook Name:: veeam
# Spec:: server
#
# Copyright (c) 2016 Exosphere Data LLC, All Rights Reserved.

require 'spec_helper'

describe 'veeam::server' do
  before do
    mock_windows_system_framework # Windows Framework Helper from 'spec/windows_helper.rb'
    stub_command('sc.exe query W3SVC').and_return 1
    stub_command(/Get-DiskImage/).and_return(false)
    stub_data_bag_item('veeam', 'license').and_return(nil)
  end
  context 'Install prequisite components' do
    platforms = {
      'windows' => {
        'versions' => %w(2008R2 2012 2012R2)
      }
    }
    platforms.each do |platform, components|
      components['versions'].each do |version|
        context "On #{platform} #{version}" do
          context 'successfully' do
            before do
              Fauxhai.mock(platform: platform, version: version)
              allow(Chef::Config).to receive(:file_cache_path)
                .and_return('...')
              # Need to set a valid .NET Framework version
              allow_any_instance_of(Chef::DSL::RegistryHelper)
                .to receive(:registry_get_values)
                .and_return([{}, {}, {}, {}, {}, {}, { data: 379893 }])
              node.normal['veeam']['server']['accept_eula'] = true
            end

            let(:runner) do
              ChefSpec::SoloRunner.new(platform: platform, version: version, file_cache_path: '/tmp/cache', step_into: ['veeam_server'])
            end
            let(:node) { runner.node }
            let(:chef_run) { runner.converge(described_recipe) }
            let(:package_save_dir) { win_friendly_path(::File.join(Chef::Config[:file_cache_path], 'package')) }
            let(:downloaded_file_name) { win_friendly_path(::File.join(package_save_dir, 'VeeamBackup&Replication_9.0.0.902.iso')) }

            it 'converges successfully' do
              expect(chef_run).to install_veeam_prerequisites('Install Veeam Prerequisites')
              expect(chef_run).to install_veeam_server('Install Veeam Backup Server')
              expect { chef_run }.not_to raise_error
            end
            it 'Step into LWRP - veeam_server' do
              expect(chef_run).to create_directory(package_save_dir)
              expect(chef_run).to create_remote_file(downloaded_file_name)
              expect(chef_run).to run_powershell_script('Load Veeam media')
              expect(chef_run).to run_ruby_block('Install the Backup server application')
              expect(chef_run).to delete_file(downloaded_file_name)
            end
            it 'should unmount the media' do
              stub_command(/Get-DiskImage/).and_return(true)
              expect(chef_run).to run_powershell_script('Dismount Veeam media')
            end
            it 'should not remove the media if keep_media is True' do
              node.override['veeam']['server']['keep_media'] = true
              expect(chef_run).not_to delete_file(downloaded_file_name)
            end
            it 'returns NO error when username and password supplied' do
              node.override['veeam']['server']['vbr_service_user'] = 'user1'
              node.override['veeam']['server']['vbr_service_password'] = 'password1'
              expect { chef_run }.not_to raise_error
            end
            it 'returns NO error when install_dir supplied' do
              node.override['veeam']['server']['install_dir'] = 'C:\\Veeam\\Backupserver'
              expect { chef_run }.not_to raise_error
            end
          end
          context 'fails' do
            before do
              Fauxhai.mock(platform: platform, version: version)
              node.normal['veeam']['server']['accept_eula'] = true
              # Need to set a valid .NET Framework version
              allow_any_instance_of(Chef::DSL::RegistryHelper)
                .to receive(:registry_get_values)
                .and_return([{}, {}, {}, {}, {}, {}, { data: 379893 }])
            end

            let(:runner) do
              ChefSpec::SoloRunner.new(platform: platform, version: version, file_cache_path: '/tmp/cache', step_into: ['veeam_server'])
            end
            let(:node) { runner.node }
            let(:chef_run) { runner.converge(described_recipe) }

            it 'raises an error about .NET Framework' do
              # Mock that no .NET Framework exists
              allow_any_instance_of(Chef::DSL::RegistryHelper)
                .to receive(:registry_get_values)
                .and_return(nil)
              expect { chef_run }.to raise_error(RuntimeError, /Microsoft .NET Framework 4.5.2 or higher be installed/)
            end
            it 'raises an error when EULA not accepted' do
              node.normal['veeam']['server']['accept_eula'] = false
              expect { chef_run }.to raise_error(ArgumentError, /The Veeam Backup and Recovery EULA must be accepted/)
            end
            it 'returns an Argument error when no password supplied' do
              node.override['veeam']['server']['vbr_service_user'] = 'user1'
              expect { chef_run }.to raise_error(ArgumentError, /The VBR service password must be set if a username is supplied/)
            end
          end
        end
      end
    end
  end
  context 'Test installation' do
    platforms = {
      'windows' => {
        'versions' => %w(2003R2) # Unable to test plain Win2008 since Fauxhai doesn't have a template for 2008
      }
    }
    platforms.each do |platform, components|
      components['versions'].each do |version|
        context "On #{platform} #{version}" do
          before do
            Fauxhai.mock(platform: platform, version: version)
          end

          let(:chef_run) do
            ChefSpec::SoloRunner.new(platform: platform, version: version).converge(described_recipe)
          end
          it 'raises an exception' do
            expect { chef_run }.to raise_error('This recipe requires a Windows 2008R2 or higher host!')
          end
        end
      end
    end
  end
end

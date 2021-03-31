shared_examples 'prints to stdout' do
  it 'prints a proper message to stdout' do
    expect { command }
      .to output(expected_output).to_stdout
      .and output('').to_stderr
  end
end

shared_examples 'does not remove files' do
  it 'does not remove any files' do
    silence_stdout do
      expect { command }
        .not_to change { Dir.glob(File.join(mirror_dir, '**', '*')).count }
    end
  end
end

shared_examples 'does not remove database entries' do
  it 'does not remove any database entries' do
    silence_stdout do
      expect { command }
        .not_to change(DownloadedFile, :count)
    end
  end
end

shared_examples 'remove files' do
  it 'remove all stale files' do
    silence_stdout do
      expect { command }
        .to change { Dir.glob(File.join(mirror_dir, '**', '*')).count }
        .by(-stale_files.count)
    end
  end
end

shared_examples 'remove source files' do
  it 'remove source files' do
    silence_stdout do
      expect { command }
        .to change { Dir.glob(File.join(mirror_dir, '**', '*.src.rpm')).count }
        .by(-stale_files.count)
    end
  end
end

shared_examples 'remove database entries' do
  it 'remove all database entries referring to stale files' do
    silence_stdout do
      expect { command }
        .to change(DownloadedFile, :count)
        .by(-stale_database_entries.count)
    end
  end
end

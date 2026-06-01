%% ====================== USER SETTINGS ======================
playDuration     = 1;                 % seconds (used only if enableOverride = true)
enableOverride   = true;              % set false to play full file
desiredPeakVolt  = 0.4;               % scale audio to ±desiredPeakVolt
aoDevice         = "PXI1Slot3";       % AO / DIO device
aoChannel        = "ao0";             % AO channel
ledLine          = "Port0/Line0";     % Digital output line = P0.0 = pin 52
triggerTerminal  = "PXI1Slot3/PFI0";  % External TTL terminal
triggerEdge      = "FallingEdge";     % "RisingEdge" or "FallingEdge"
numTrigPerRun    = 1;                 % one TTL per run
trigTimeout_ms   = 1000;              % shorter timeout so stop control stays responsive
folderWithWavs   = pwd;               % directory containing the .wav files

%% ====================== FILE SELECTION ======================
files = dir(fullfile(folderWithWavs,'*.wav'));
if isempty(files)
    error('Need at least 1 .wav file in: %s', folderWithWavs);
end

choices = {files.name};
idx = menu('Select WAV to play repeatedly', choices{:});
if idx == 0
    error('No selection made.');
end

filename = choices{idx};
filePath = fullfile(folderWithWavs, filename);

%% ====================== READ / PREP AUDIO ======================
[audioData, fs] = audioread(filePath);
if size(audioData,2) > 1
    warning('Stereo file detected. Using left channel only.');
    audioData = audioData(:,1);
end

audioData = audioData ./ max(1e-12, max(abs(audioData)));
outputSignal = desiredPeakVolt * audioData;

%% ====================== FIND SOUND SEGMENTS ======================
env = movmean(abs(outputSignal), round(0.002 * fs));
thresh = 0.1 * max(env);
isSound = env > thresh;

d = diff([0; isSound; 0]);
onIdx  = find(d ==  1);
offIdx = find(d == -1) - 1;

if isempty(onIdx)
    warning('No sound segments detected above threshold. Check "thresh".');
else
    onTimes_s  = (onIdx  - 1) / fs;
    offTimes_s = (offIdx - 1) / fs;

    onTimes_ms  = round(onTimes_s  * 1000);
    offTimes_ms = round(offTimes_s * 1000);

    fprintf('\nDetected %d sound segment(s):\n', numel(onTimes_ms));
    for k = 1:numel(onTimes_ms)
        fprintf(' Segment %d: ON at %.1f ms, OFF at %.1f ms\n', ...
            k, onTimes_ms(k), offTimes_ms(k));
    end
end

%% ====================== DURATION OVERRIDE ======================
if enableOverride
    samplesNeeded = round(playDuration * fs);
    if numel(outputSignal) >= samplesNeeded
        outputSignal = outputSignal(1:samplesNeeded);
    else
        outputSignal(end+1:samplesNeeded,1) = 0;
    end
    playSeconds = playDuration;
else
    playSeconds = numel(outputSignal) / fs;
end

v_pp = max(outputSignal) - min(outputSignal);
fprintf('\nSelected: %s\n', filename);
fprintf('Sample Rate: %d Hz | Duration: %.2f s | Vpp: %.3f V\n', fs, playSeconds, v_pp);

%% ====================== BUILD LED SIGNAL ======================
% LED HIGH during playback window only
ledSignal = true(size(outputSignal,1), 1);

% Combine outputs:
%   col 1 = analog audio on ao0
%   col 2 = digital LED on Port0/Line0
queuedData = [outputSignal, ledSignal];

%% ====================== DAQ SETUP (NI) ======================
s = daq.createSession('ni');
addAnalogOutputChannel(s, char(aoDevice), char(aoChannel), 'Voltage');
addDigitalChannel(s, char(aoDevice), char(ledLine), 'OutputOnly');
s.Rate = fs;

%% ====================== TRIGGER CONFIGURATION ======================
addTriggerConnection(s, 'External', triggerTerminal, 'StartTrigger');
s.TriggersPerRun = numTrigPerRun;
s.ExternalTriggerTimeout = trigTimeout_ms / 1000;
s.Connections(1).TriggerCondition = triggerEdge;

%% ====================== STOP CONTROL WINDOW ======================
stopFig = figure( ...
    'Name', 'Armed Trigger Control', ...
    'NumberTitle', 'off', ...
    'MenuBar', 'none', ...
    'ToolBar', 'none', ...
    'Color', [0.94 0.94 0.94], ...
    'Position', [500 500 360 140], ...
    'CloseRequestFcn', @(src,evt)setappdata(src,'stopRequested',true));

setappdata(stopFig, 'stopRequested', false);

uicontrol(stopFig, ...
    'Style', 'text', ...
    'String', sprintf('Armed cue: %s', filename), ...
    'FontSize', 10, ...
    'Position', [20 90 320 25], ...
    'BackgroundColor', [0.94 0.94 0.94]);

uicontrol(stopFig, ...
    'Style', 'pushbutton', ...
    'String', 'STOP ARMED TRIGGER', ...
    'FontSize', 12, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', [1 1 1], ...
    'BackgroundColor', [0.8 0.1 0.1], ...
    'Position', [80 28 200 45], ...
    'Callback', @(src,evt)setappdata(stopFig,'stopRequested',true));

drawnow;

%% ====================== ARM / RE-ARM LOOP ======================
fprintf('\nSystem armed.\n');
fprintf('Each %s TTL on %s will play the selected cue and drive %s HIGH only during playback.\n', ...
    triggerEdge, triggerTerminal, ledLine);
fprintf('Press the STOP ARMED TRIGGER button when finished.\n\n');

trialCount = 0;

while ishandle(stopFig) && ~getappdata(stopFig,'stopRequested')

    % Idle state while waiting
    outputSingleScan(s, [0 false]);

    % Queue combined analog + digital data before every arm
    queueOutputData(s, queuedData);

    fprintf('Armed. Waiting for %s TTL on %s ...\n', triggerEdge, triggerTerminal);

    try
        % Wait for one TTL, then audio + LED run together
        s.startForeground();

        % Return to idle immediately after playback
        outputSingleScan(s, [0 false]);

        trialCount = trialCount + 1;
        fprintf('Playback %d complete. Re-arming...\n', trialCount);

    catch ME
        try
            outputSingleScan(s, [0 false]);
        catch
        end

        if contains(lower(ME.message), 'timeout')
            drawnow;
            continue;
        else
            if ishandle(stopFig)
                delete(stopFig);
            end
            release(s);
            daqreset;
            rethrow(ME);
        end
    end

    drawnow;
end

%% ====================== FINAL SAFE STATE ======================
try
    outputSingleScan(s, [0 false]);
catch
end

%% ====================== CLEANUP ======================
if ishandle(stopFig)
    delete(stopFig);
end

release(s);
daqreset;

fprintf('\nStopped by user.\n');
fprintf('Total playbacks: %d\n', trialCount);
fprintf('Playback complete. LED off.\n');

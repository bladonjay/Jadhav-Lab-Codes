%% wav file analysis
[fileToRead1,dir1]=uigetfile;
newData1 = importdata(fullfile(dir1,fileToRead1));

% Create new variables in the base workspace from those fields.
vars = fieldnames(newData1);
for i = 1:length(vars)
    assignin('base', vars{i}, newData1.(vars{i}));
end
%%

timewin=[60 120];

window=timewin*fs;


data2=(data(window(1):window(2)));
T = 1/fs;             % Sampling period       
L = length(data2);             % Length of signal
t = (0:L-1)*T;   

y=fft(data2(:,1));

p2=abs(y/L); %
p1=p2(1:L/2+1); % nyquist?

f=fs*(0:(L/2))/L;
figure;

plot(f,p1);
title('Single-Sided Amplitude Spectrum of X(t)')
xlabel('f (Hz)')
ylabel('|P1(f)|')


%% using gpu code to get a cwt on some data


[s,f,t]=spectrogram(data,64,[],[35000:200:60000],fs);

figure; imagesc(t,f,abs(s))


figure; imagesc(t,f,SmoothMat2(zscore(abs(s),[],2)>5,[5 5],2));


% zooming in to a putative call

window = [51 51.5];

wininds=round(window.*fs);

[s,f,t]=spectrogram(data(wininds(1):wininds(2)),36,24,[35000:100:60000],fs);
figure; imagesc(t,f,SmoothMat2(abs(s),[10 10],1));



%% deepsqueak code:
% this comes from the function SqueakDetect:

% 
Calls = table();

%chunksize=?
% overlap = ?
% cutoffs (HighCutoff LowCutoff)
% ScoreCutoff
%u = sum(hamming(wind).^2) % not sure what this does

wind = round(wind * audio_info.SampleRate);
noverlap = round(noverlap * audio_info.SampleRate);
nfft = round(nfft * audio_info.SampleRate);

% Break the audio file into chunks
chunks = linspace(1,(DetectLength - overlap) * audio_info.SampleRate,round(DetectLength / chunksize));
for i = 1:length(chunks)-1
    try
        DetectStart = tic;
        
        % Get the audio windows
        windL = chunks(i);
        windR = chunks(i+1) + overlap*audio_info.SampleRate;
        
        % Read the audio
        audio = audioread(audio_info.Filename,floor([windL, windR]));
        
        %% Mix multichannel audio:
        % By default, take the mean of multichannel audio. 
        % Another method could be to take the max of the multiple channels,
        % or just take the first channel.
        audio = audio - mean(audio,1);
        switch 'mean'
            case 'first'
                audio = audio(:,1);
            case 'mean'
                audio = mean(audio,2);
            case 'max'
                [~,index] = max(abs(audio'));
                audio = audio(sub2ind(size(audio),1:size(audio,1),index));
        end

        % Create the spectrogram
        [s,fr,ti] = spectrogram(audio(:,1),wind,noverlap,nfft,audio_info.SampleRate,'yaxis'); % Just use the first audio channel
        upper_freq = find(fr>=HighCutoff*1000,1);
        lower_freq = find(fr>=LowCutoff*1000,1);
        
        % Extract the region within the frequency range
        s = s(lower_freq:upper_freq,:);
        s = flip(abs(s),1);
        
        % Normalize gain setting (Allows for modified precision/recall
        % tolerance)
        med=median(s(:));
        
        scale_factor = [
            .1 .65 .9  
            30 20 10
            ];

        for iteration = 1:number_of_repeats
            
            im = mat2gray(s,[scale_factor(1,iteration)*med scale_factor(2,iteration)*med]);
            
            % Subtract the 5th percentile to remove horizontal noise bands
            im = im - prctile(im,5,2);
            
            % Detect!
            [bboxes, scores, Class] = detect(network, im2uint8(im), 'ExecutionEnvironment','auto','NumStrongestRegions',Inf);
            
            % Calculate each call's power
            Power = [];
            for j = 1:size(bboxes,1)
                % Get the maximum amplitude of the region within the box
                amplitude = max(max(...
                    s(bboxes(j,2):bboxes(j,2)+bboxes(j,4)-1,bboxes(j,1):bboxes(j,3)+bboxes(j,1)-1)));
                
                % convert amplitude to PSD
                callPower = amplitude.^2 / U;
                callPower = 2*callPower / audio_info.SampleRate;
                % Convert power to db
                callPower = 10 * log10(callPower);
                
                Power = [Power
                    callPower];
            end
            
            % Convert boxes from pixels to time and kHz
            bboxes(:,1) = ti(bboxes(:,1)) + (windL ./ audio_info.SampleRate);
            bboxes(:,2) = fr(upper_freq - (bboxes(:,2) + bboxes(:,4))) ./ 1000;
            bboxes(:,3) = ti(bboxes(:,3));
            bboxes(:,4) = fr(bboxes(:,4)) ./ 1000;
            
            % Concatinate the results
            AllBoxes=[AllBoxes
                bboxes(Class == 'USV',:)];
            AllScores=[AllScores
                scores(Class == 'USV',:)];
            AllClass=[AllClass
                Class(Class == 'USV',:)];
            AllPowers=[AllPowers
                Power(Class == 'USV',:)];
        end

            t = toc(DetectStart);
            waitbar(...
                i/(length(chunks)-1),...
                h,...
                sprintf(['Detection Speed: ' num2str((chunksize + overlap) / t,'%.1f') 'x  Call Fragments Found:' num2str(length(AllBoxes(:,1))/number_of_repeats,'%.0f') '\n File ' num2str(currentFile) ' of ' num2str(totalFiles)]));
          
    catch ME
        waitbar(...
            i/(length(chunks)-1),...
            h,...
            sprintf('Error in Network, Skiping Audio Chunk'));
        disp('Error in Network, Skiping Audio Chunk');
        warning( getReport( ME, 'extended', 'hyperlinks', 'on' ) );
    end
end
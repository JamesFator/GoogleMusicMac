/*
 * js/main.js
 *
 * This script is part of the JavaScript interface used to interact with
 * the Google Music page, in order to provide notifications functionality.
 *
 * Created by Sajid Anwar.
 *
 * Subject to terms and conditions in LICENSE.md.
 *
 */

// This check ensures that, even though this script is run multiple times, our code is only attached once.
if (typeof window.MusicAPI === 'undefined') {
    window.MusicAPI = {};

    var lastTitle = "";
    var lastArtist = "";
    var lastAlbum = "";

    var addObserver = new MutationObserver(function(mutations) {
        mutations.forEach(function(m) {
            for (var i = 0; i < m.addedNodes.length; i++) {
                var target = m.addedNodes[i];
                var name = target.id || target.className;

                if (name == 'text-wrapper')  {
                    var now = new Date();

                    var title = document.querySelector('#playerSongTitle');
                    var artist = document.querySelector('#player-artist');
                    var album = document.querySelector('.player-album');
                    var art = document.querySelector('#playingAlbumArt');
                    var time = document.querySelector('#time_container_duration');

                    title = (title) ? title.innerText : 'Unknown';
                    artist = (artist) ? artist.innerText : 'Unknown';
                    album = (album) ? album.innerText : 'Unknown';
                    art = (art) ? art.src : null;
                    time = (time) ? time.innerText : 'Unknown';

                    // The art may be a protocol-relative URL, so normalize it to HTTPS.
                    if (art && art.slice(0, 2) === '//') {
                        art = 'https:' + art;
                    }

                    // Make sure that this is the first of the notifications for the
                    // insertion of the song information elements.
                    if (lastTitle != title || lastArtist != artist || lastAlbum != album) {
                        window.googleMusicApp.notifySong(title, artist, album, art, time);

                        lastTitle = title;
                        lastArtist = artist;
                        lastAlbum = album;
                    }
                }
            }
        });
    });

    addObserver.observe(document.querySelector('#playerSongInfo'), { childList: true, subtree: true });
}